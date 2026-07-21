import ServiceManagement
import Sparkle
import SwiftUI

struct SettingsView: View {
    var updater: SPUUpdater? = nil

    @AppStorage("haURL") private var haURL = ""
    @AppStorage("disabledIntegrations") private var disabledIntegrationsStr = ""
    @AppStorage("requiredLabels") private var requiredLabelsStr = ""
    @AppStorage("hudShowPercentage") private var hudShowPercentage = false
    @State private var haToken = ""

    @Environment(HAService.self) private var service
    @Environment(VolumeKeyInterceptor.self) private var interceptor

    @State private var hasAccessibilityPermission = VolumeKeyInterceptor.hasAccessibilityPermission
    @State private var lastUpdateCheckDate: Date?
    @State private var updateCheckObservation: NSKeyValueObservation?
    @State private var permissionPollingTask: Task<Void, Never>?
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    private var launchAtLoginToggle: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                if enabled {
                    try? SMAppService.mainApp.register()
                    launchAtLogin = (SMAppService.mainApp.status == .enabled)
                } else {
                    Task {
                        try? await SMAppService.mainApp.unregister()
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
                }
            }
        )
    }

    private var interceptorToggle: Binding<Bool> {
        Binding(
            get: { interceptor.isEnabled },
            set: { enabled in
                if enabled {
                    let granted = interceptor.enable()
                    UserDefaults.standard.set(granted, forKey: "interceptVolumeKeys")
                } else {
                    interceptor.disable()
                    UserDefaults.standard.set(false, forKey: "interceptVolumeKeys")
                }
            }
        )
    }

    var body: some View {
        let _ = interceptor.isEnabled
        TabView {
            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 450)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            haToken = KeychainHelper.load(forKey: "haToken")
            hasAccessibilityPermission = VolumeKeyInterceptor.hasAccessibilityPermission
            lastUpdateCheckDate = updater?.lastUpdateCheckDate
            updateCheckObservation = updater?.observe(\.lastUpdateCheckDate) { updater, _ in
                lastUpdateCheckDate = updater.lastUpdateCheckDate
            }
            permissionPollingTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    hasAccessibilityPermission = VolumeKeyInterceptor.hasAccessibilityPermission
                }
            }
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
            updateCheckObservation?.invalidate()
            updateCheckObservation = nil
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
        }
    }

    private var settingsTab: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    sectionLabel("General")
                    Toggle("Launch at login", isOn: launchAtLoginToggle)
                        .toggleStyle(.checkbox)
                }

                settingsDivider

                GridRow {
                    sectionLabel("Connection")
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("URL", text: $haURL, prompt: Text("http://homeassistant.local:8123"))
                            .onChange(of: haURL) { _, new in
                                service.configure(url: new, token: haToken, entityID: service.entityID)
                            }
                        SecureField("Token", text: $haToken, prompt: Text("Long-lived access token"))
                            .onChange(of: haToken) { _, new in
                                KeychainHelper.save(new, forKey: "haToken")
                                service.configure(url: haURL, token: new, entityID: service.entityID)
                            }
                    }
                }

                settingsDivider

                GridRow {
                    sectionLabel("Volume Keys")
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Intercept hardware volume keys", isOn: interceptorToggle)
                            .toggleStyle(.checkbox)
                            .disabled(!hasAccessibilityPermission)
                        Text("Captures volume up/down keys system-wide and adjusts the media player instead. Requires Accessibility permission.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !hasAccessibilityPermission {
                            Button("Grant Accessibility Permission") {
                                VolumeKeyInterceptor.requestAccessibilityPermission()
                            }
                        }
                        Toggle("Show percentage in volume HUD", isOn: $hudShowPercentage)
                            .toggleStyle(.checkbox)
                    }
                }

                if !service.allLabels.isEmpty {
                    settingsDivider

                    GridRow {
                        sectionLabel("Labels")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("When labels are selected, only entities that carry at least one of them are shown. Selecting none shows all entities.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(service.allLabels, id: \.self) { label in
                                let isRequired = Binding<Bool>(
                                    get: {
                                        let required = Set(requiredLabelsStr.split(separator: ",").filter { !$0.isEmpty }.map(String.init))
                                        return required.contains(label)
                                    },
                                    set: { enabled in
                                        var required = Set(requiredLabelsStr.split(separator: ",").filter { !$0.isEmpty }.map(String.init))
                                        if enabled {
                                            required.insert(label)
                                        } else {
                                            required.remove(label)
                                        }
                                        requiredLabelsStr = required.sorted().joined(separator: ",")
                                    }
                                )
                                Toggle(isOn: isRequired) {
                                    Text(service.labelNames[label] ?? label
                                        .replacingOccurrences(of: "_", with: " ")
                                        .replacingOccurrences(of: "-", with: " ")
                                        .capitalized)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }

                if !service.integrations.isEmpty {
                    settingsDivider

                    GridRow {
                        sectionLabel("Integrations")
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(service.integrations) { integration in
                                let isEnabled = Binding<Bool>(
                                    get: {
                                        let disabled = Set(disabledIntegrationsStr.split(separator: ",").filter { !$0.isEmpty }.map(String.init))
                                        return !disabled.contains(integration.platform)
                                    },
                                    set: { enabled in
                                        var disabled = Set(disabledIntegrationsStr.split(separator: ",").filter { !$0.isEmpty }.map(String.init))
                                        if enabled {
                                            disabled.remove(integration.platform)
                                        } else {
                                            disabled.insert(integration.platform)
                                        }
                                        disabledIntegrationsStr = disabled.sorted().joined(separator: ",")
                                    }
                                )
                                Toggle(isOn: isEnabled) {
                                    HStack(spacing: 6) {
                                        Image(systemName: integration.icon)
                                            .frame(width: 16, alignment: .center)
                                        Text(integration.displayName)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        (Text(key) + Text(verbatim: ":"))
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private var settingsDivider: some View {
        Divider().padding(.vertical, 4)
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "HA Volume Control")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Link("GitHub", destination: URL(string: "https://github.com/microcode/ha-volume-control/")!)
                .font(.subheadline)

            if let updater {
                Button("Check for Updates…") { updater.checkForUpdates() }
            }

            if let date = lastUpdateCheckDate {
                Text("Last check: \(formattedCheckDate(date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Never checked for updates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func formattedCheckDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}

#Preview {
    SettingsView()
}
