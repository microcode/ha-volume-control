import Foundation
import Observation
import os

private let wsLog = Logger(subsystem: "HA-Volume-Control", category: "websocket")
private let eventLog = Logger(subsystem: "HA-Volume-Control", category: "events")
private let registryLog = Logger(subsystem: "HA-Volume-Control", category: "registry")
private let restLog = Logger(subsystem: "HA-Volume-Control", category: "rest")

struct HAIntegration: Identifiable, Hashable {
    let platform: String
    var id: String {
        platform
    }

    var displayName: String {
        let known: [String: String] = [
            "apple_tv": "Apple TV",
            "cast": "Google Cast",
            "samsungtv": "Samsung TV",
            "webostv": "LG webOS",
            "androidtv": "Android TV",
            "vlc_telnet": "VLC",
            "squeezebox": "Logitech Media Server",
        ]
        return known[platform] ?? platform
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var icon: String {
        HAIcons.sfSymbol(forPlatform: platform)
    }
}

@Observable
final class HAService {
    var volume: Double = 0.5
    var isMuted: Bool = false
    var isConnected: Bool = false
    var entityID: String = ""
    var friendlyName: String = ""
    private(set) var integrations: [HAIntegration] = []
    private(set) var platformByEntityID: [String: String] = [:]
    private(set) var disabledOrHiddenEntityIDs: Set<String> = []
    private(set) var labelsByEntityID: [String: Set<String>] = [:]
    private(set) var allLabels: [String] = []
    private(set) var labelNames: [String: String] = [:]
    private(set) var iconsByEntityID: [String: String] = [:]

    private var baseURL: String = ""
    private var token: String = ""

    private var webSocketTask: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var nextMessageID = 1
    private var registryRequestID = 0
    private var labelRegistryRequestID = 0

    func configure(url: String, token: String, entityID: String) {
        let needsReconnect = url != baseURL || token != self.token
        baseURL = url
        self.token = token
        self.entityID = entityID
        if needsReconnect {
            startWebSocket()
        }
    }

    // MARK: - WebSocket streaming

    private func startWebSocket() {
        if connectionTask != nil {
            wsLog.info("Cancelling existing connection before reconnect")
        }
        connectionTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false

        guard !baseURL.isEmpty, !token.isEmpty else {
            wsLog.debug("Skipping WebSocket start — URL or token not configured")
            return
        }

        let wsBase = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let url = URL(string: "\(wsBase)/api/websocket") else {
            wsLog.error("Invalid WebSocket URL derived from base URL: \(baseURL)")
            return
        }

        wsLog.info("Connecting to \(url.absoluteString, privacy: .public)")
        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        connectionTask = Task { [weak self] in
            await self?.runWebSocket(task: task)
        }
    }

    private func runWebSocket(task: URLSessionWebSocketTask) async {
        do {
            // 1. auth_required
            _ = try await task.receive()
            wsLog.debug("Received auth_required")

            // 2. authenticate
            try await task.send(.string("{\"type\":\"auth\",\"access_token\":\"\(token)\"}"))
            wsLog.debug("Sent auth request")

            // 3. auth_ok / auth_invalid
            let authMsg = try await task.receive()
            guard case let .string(authStr) = authMsg,
                  let authData = authStr.data(using: .utf8),
                  let authJSON = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
                  authJSON["type"] as? String == "auth_ok"
            else {
                wsLog.error("Authentication failed")
                isConnected = false
                return
            }
            wsLog.info("Authenticated successfully")

            // 4. request entity registry to discover media player platforms
            let regID = nextMessageID; nextMessageID += 1
            registryRequestID = regID
            try await task.send(.string("{\"id\":\(regID),\"type\":\"config/entity_registry/list\"}"))
            wsLog.debug("Sent entity registry request (id=\(regID))")

            // 4b. request label registry to resolve label IDs to display names
            let labelRegID = nextMessageID; nextMessageID += 1
            labelRegistryRequestID = labelRegID
            try await task.send(.string("{\"id\":\(labelRegID),\"type\":\"config/label_registry/list\"}"))
            wsLog.debug("Sent label registry request (id=\(labelRegID))")

            isConnected = true

            // 6. route incoming messages
            while !Task.isCancelled {
                let message = try await task.receive()
                if case let .string(text) = message {
                    wsLog.debug("Received message: \(text, privacy: .public)")
                    handleMessage(text)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            wsLog.error("WebSocket error: \(error.localizedDescription, privacy: .public) — retrying in 5s")
            isConnected = false
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            startWebSocket()
        }
    }

    private func handleTriggerEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "event",
              let event = json["event"] as? [String: Any],
              let variables = event["variables"] as? [String: Any],
              let trigger = variables["trigger"] as? [String: Any] else { return }

        let triggerEntityID = trigger["entity_id"] as? String ?? "<unknown>"
        guard triggerEntityID == entityID else {
            eventLog.debug("Ignoring state change for \(triggerEntityID, privacy: .public) (selected: \(entityID, privacy: .public))")
            return
        }

        guard let toState = trigger["to_state"] as? [String: Any],
              let attributes = toState["attributes"] as? [String: Any]
        else {
            eventLog.error("Trigger event for \(triggerEntityID, privacy: .public) missing to_state/attributes")
            return
        }

        if let vol = attributes["volume_level"] as? Double {
            volume = vol
        }
        if let muted = attributes["is_volume_muted"] as? Bool {
            isMuted = muted
        }
        if let name = attributes["friendly_name"] as? String {
            friendlyName = name
        }

        eventLog.info("State update for \(triggerEntityID, privacy: .public): volume=\(volume, format: .fixed(precision: 2)) muted=\(isMuted) name=\(friendlyName, privacy: .public)")
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if json["type"] as? String == "result", let msgID = json["id"] as? Int {
            if msgID == registryRequestID,
               let entries = json["result"] as? [[String: Any]]
            {
                handleRegistryResult(entries)
            } else if msgID == labelRegistryRequestID,
                      let entries = json["result"] as? [[String: Any]]
            {
                handleLabelRegistryResult(entries)
            }
        } else if json["type"] as? String == "event" {
            handleTriggerEvent(text)
        }
    }

    private func handleRegistryResult(_ entries: [[String: Any]]) {
        registryLog.info("Processing entity registry: \(entries.count) total entries")
        var platformMap: [String: String] = [:]
        var suppressedIDs: Set<String> = []
        var labelMap: [String: Set<String>] = [:]
        var iconMap: [String: String] = [:]
        for entry in entries {
            guard let entityID = entry["entity_id"] as? String,
                  entityID.hasPrefix("media_player."),
                  let platform = entry["platform"] as? String else { continue }
            // disabled_by / hidden_by are null when the entity is enabled/visible;
            // any non-null string value means HA or the user has suppressed it.
            let isDisabled = entry["disabled_by"] as? String != nil
            let isHidden = entry["hidden_by"] as? String != nil
            let labels = entry["labels"] as? [String] ?? []
            if isDisabled || isHidden {
                registryLog.debug("Suppressed entity: \(entityID, privacy: .public) (disabled=\(isDisabled) hidden=\(isHidden))")
                suppressedIDs.insert(entityID)
            } else {
                registryLog.debug("Entity: \(entityID, privacy: .public) platform=\(platform, privacy: .public) labels=\(labels, privacy: .public)")
                platformMap[entityID] = platform
                if let icon = entry["icon"] as? String {
                    iconMap[entityID] = icon
                }
            }
            if !labels.isEmpty {
                labelMap[entityID] = Set(labels)
            }
        }
        platformByEntityID = platformMap
        disabledOrHiddenEntityIDs = suppressedIDs
        labelsByEntityID = labelMap
        iconsByEntityID = iconMap
        allLabels = Set(labelMap.values.joined()).sorted()
        integrations = Set(platformMap.values).sorted().map { HAIntegration(platform: $0) }
        registryLog.info("Entity registry done: \(platformMap.count) active, \(suppressedIDs.count) suppressed, \(integrations.count) integration(s), \(allLabels.count) label(s)")
        subscribeToMediaPlayerEntities(Array(platformMap.keys))
    }

    private func subscribeToMediaPlayerEntities(_ entityIDs: [String]) {
        guard !entityIDs.isEmpty, let task = webSocketTask else {
            wsLog.debug("Skipping subscription — no active entities or no WebSocket")
            return
        }
        let idList = entityIDs.sorted().map { "\"\($0)\"" }.joined(separator: ",")
        let subID = nextMessageID; nextMessageID += 1
        let msg = "{\"id\":\(subID),\"type\":\"subscribe_trigger\",\"trigger\":{\"platform\":\"state\",\"entity_id\":[\(idList)]}}"
        wsLog.info("Subscribing to \(entityIDs.count) entity/entities (id=\(subID))")
        Task {
            do {
                try await task.send(.string(msg))
            } catch {
                wsLog.error("Failed to send subscription: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleLabelRegistryResult(_ entries: [[String: Any]]) {
        var names: [String: String] = [:]
        for entry in entries {
            guard let id = entry["label_id"] as? String,
                  let name = entry["name"] as? String else { continue }
            registryLog.debug("Label: \(id, privacy: .public) → \(name, privacy: .public)")
            names[id] = name
        }
        labelNames = names
        registryLog.info("Label registry done: \(names.count) label(s)")
    }

    deinit {
        connectionTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: - REST API

    func fetchVolume() async {
        guard !baseURL.isEmpty, !token.isEmpty, !entityID.isEmpty,
              let requestURL = URL(string: "\(baseURL)/api/states/\(entityID)")
        else {
            isConnected = false
            return
        }

        restLog.info("GET \(requestURL.absoluteString, privacy: .public)")
        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                restLog.error("fetchVolume failed: HTTP \(status)")
                isConnected = false
                return
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let attributes = json["attributes"] as? [String: Any],
               let vol = attributes["volume_level"] as? Double
            {
                volume = vol
                isMuted = attributes["is_volume_muted"] as? Bool ?? false
                friendlyName = attributes["friendly_name"] as? String ?? ""
                isConnected = true
                restLog.info("fetchVolume: volume=\(vol, format: .fixed(precision: 2)) muted=\(isMuted) name=\(friendlyName, privacy: .public)")
            } else {
                restLog.error("fetchVolume: unexpected response body")
                isConnected = false
            }
        } catch {
            restLog.error("fetchVolume error: \(error.localizedDescription, privacy: .public)")
            isConnected = false
        }
    }

    func setMute(_ muted: Bool? = nil) async {
        guard !baseURL.isEmpty, !token.isEmpty, !entityID.isEmpty,
              let requestURL = URL(string: "\(baseURL)/api/services/media_player/volume_mute") else { return }

        let newMuted = muted ?? !isMuted
        isMuted = newMuted
        restLog.info("POST volume_mute → \(newMuted) for \(entityID, privacy: .public)")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["entity_id": entityID, "is_volume_muted": newMuted]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                isConnected = (200 ..< 300).contains(httpResponse.statusCode)
                if !isConnected {
                    restLog.error("setMute failed: HTTP \(httpResponse.statusCode)")
                    isMuted = !newMuted
                }
            }
        } catch {
            restLog.error("setMute error: \(error.localizedDescription, privacy: .public)")
            isConnected = false
            isMuted = !newMuted
        }
    }

    func setVolume(_ value: Double) async {
        guard !baseURL.isEmpty, !token.isEmpty, !entityID.isEmpty,
              let requestURL = URL(string: "\(baseURL)/api/services/media_player/volume_set") else { return }

        volume = value

        restLog.info("POST volume_set → \(value, format: .fixed(precision: 2)) for \(entityID, privacy: .public)")

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["entity_id": entityID, "volume_level": value]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                isConnected = (200 ..< 300).contains(httpResponse.statusCode)
                if !isConnected {
                    restLog.error("setVolume failed: HTTP \(httpResponse.statusCode)")
                }
            }

            if isConnected, isMuted {
                await setMute(false)
            }
        } catch {
            restLog.error("setVolume error: \(error.localizedDescription, privacy: .public)")
            isConnected = false
        }
    }
}
