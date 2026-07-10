import SwiftUI

struct MediaPlayer: Identifiable {
    var id: String {
        entityID
    }

    let entityID: String
    let friendlyName: String

    var displayName: String {
        friendlyName.isEmpty ? entityID : friendlyName
    }

    var icon: String {
        let lower = entityID.lowercased()
        if lower.contains("appletv") {
            return "appletv"
        }
        if lower.contains("homepod") {
            return "homepod.fill"
        }
        if lower.contains("tv") || lower.contains("tele") {
            return "tv"
        }
        if lower.contains("airpod") {
            return "airpodspro"
        }
        return "hifispeaker.fill"
    }
}

private struct MediaPlayerRow: View {
    let player: MediaPlayer
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: player.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? Color.white : Color.secondary)
            }

            Text("\(player.displayName) \(Text("(\(player.entityID))").foregroundStyle(.tertiary))")
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

/// Measures the rendered height of the popup content from inside SwiftUI's layout system.
private struct PopupHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContentView: View {
    @AppStorage("haURL") private var haURL = ""
    @AppStorage("haEntityID") private var haEntityID = ""
    private var haToken: String {
        KeychainHelper.load(forKey: "haToken")
    }

    @AppStorage("disabledIntegrations") private var disabledIntegrationsStr = ""
    @AppStorage("requiredLabels") private var requiredLabelsStr = ""
    @Environment(\.openSettings) private var openSettings
    @Environment(HAService.self) private var service
    @Environment(VolumeKeyInterceptor.self) private var interceptor

    @State private var sliderValue: Double = 0.5
    @State private var isEditing = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var mediaPlayers: [MediaPlayer] = []
    @State private var isLoadingPlayers = false

    private var filteredPlayers: [MediaPlayer] {
        let disabledIntegrations = Set(disabledIntegrationsStr.split(separator: ",").filter { !$0.isEmpty }.map(String.init))
        let storedLabels = Set(requiredLabelsStr.split(separator: ",").filter { !$0.isEmpty }.map(String.init))
        let requiredLabels = storedLabels.intersection(service.allLabels)
        return mediaPlayers.filter { player in
            guard !service.disabledOrHiddenEntityIDs.contains(player.entityID) else { return false }
            if !requiredLabels.isEmpty {
                let playerLabels = service.labelsByEntityID[player.entityID] ?? []
                guard !requiredLabels.isDisjoint(with: playerLabels) else { return false }
            }
            guard !disabledIntegrations.isEmpty else { return true }
            guard let platform = service.platformByEntityID[player.entityID] else { return true }
            return !disabledIntegrations.contains(platform)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("HA Volume Control")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                Button {
                    sliderValue = max(0, sliderValue - 0.10)
                } label: {
                    Image(systemName: "speaker")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Slider(value: $sliderValue, in: 0 ... 1) { editing in
                    isEditing = editing
                }

                Button {
                    sliderValue = min(1, sliderValue + 0.10)
                } label: {
                    Image(systemName: "speaker.wave.3")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .onChange(of: sliderValue) { _, newValue in
                    guard abs(newValue - service.volume) > 0.001 else { return }
                    service.volume = newValue
                    debounceTask?.cancel()
                    debounceTask = Task {
                        do {
                            try await Task.sleep(for: .milliseconds(300))
                            await service.setVolume(newValue)
                        } catch {}
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            if isLoadingPlayers && mediaPlayers.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                    Text("Loading…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filteredPlayers) { player in
                            MediaPlayerRow(player: player, isActive: player.entityID == haEntityID)
                                .onTapGesture { selectPlayer(player) }
                        }
                    }
                }
                .frame(height: CGFloat(min(filteredPlayers.count, 20)) * 36)
                .scrollIndicators(filteredPlayers.count > 20 ? .automatic : .hidden)
            }

            Divider()

            HStack(spacing: 0) {
                footerButton("Settings") {
                    openSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows
                            .filter { !($0 is NSPanel) && $0.isVisible }
                            .forEach { $0.makeKeyAndOrderFront(nil) }
                    }
                }
                Divider().frame(height: 16)
                footerButton("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280)
        .background(GeometryReader { geo in
            Color.clear.preference(key: PopupHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(PopupHeightKey.self) { height in
            guard height > 10 else { return }
            let screen = NSScreen.main ?? NSScreen.screens[0]
            // Exclude the HUD panel (level .screenSaver) to find only the MenuBarExtra popup
            guard let popup = NSApp.windows.first(where: { window in
                window is NSPanel &&
                    window.level != .screenSaver &&
                    abs(window.frame.maxY - screen.visibleFrame.maxY) < 50
            }) else { return }
            guard abs(popup.frame.height - height) > 0.5 else { return }
            var frame = popup.frame
            frame.origin.y += frame.height - height // keep top edge anchored at menu bar
            frame.size.height = height
            popup.setFrame(frame, display: popup.isVisible, animate: false)
        }
        .onAppear {
            service.configure(url: haURL, token: haToken, entityID: haEntityID)
            Task {
                await service.fetchVolume()
                if !isEditing {
                    sliderValue = service.volume
                }
            }
            Task { await loadMediaPlayers() }

            // The popup is on screen right now — capture its midX so the HUD
            // can center itself under the menu bar icon.
            if let screen = NSScreen.main,
               let popup = NSApp.windows.first(where: { window in
                   window is NSPanel && window.isVisible &&
                       abs(window.frame.maxY - screen.visibleFrame.maxY) < 30
               })
            {
                interceptor.hud?.noteIconCenter(popup.frame.midX)
            }
        }
        .onChange(of: service.volume) { _, newValue in
            if !isEditing {
                sliderValue = newValue
            }
        }
    }

    private func footerButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private func selectPlayer(_ player: MediaPlayer) {
        haEntityID = player.entityID
        service.configure(url: haURL, token: haToken, entityID: player.entityID)
        Task { await service.fetchVolume() }
    }

    private func loadMediaPlayers() async {
        guard !haURL.isEmpty, !haToken.isEmpty,
              let url = URL(string: "\(haURL)/api/states") else { return }

        isLoadingPlayers = true
        defer { isLoadingPlayers = false }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(haToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let states = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            mediaPlayers = []
            return
        }

        mediaPlayers = states
            .compactMap { state -> MediaPlayer? in
                guard let entityID = state["entity_id"] as? String,
                      entityID.hasPrefix("media_player.") else { return nil }
                let attributes = state["attributes"] as? [String: Any] ?? [:]
                let friendlyName = attributes["friendly_name"] as? String ?? ""
                return MediaPlayer(entityID: entityID, friendlyName: friendlyName)
            }
            .sorted { $0.displayName < $1.displayName }
    }
}

#Preview {
    ContentView()
}
