import SwiftUI

struct SettingsView: View {
    @AppStorage("haURL") private var haURL = ""
    @AppStorage("disabledIntegrations") private var disabledIntegrationsStr = ""
    @AppStorage("requiredLabels") private var requiredLabelsStr = ""
    @AppStorage("hudShowPercentage") private var hudShowPercentage = false
    @State private var haToken = ""

    @Environment(HAService.self) private var service
    @Environment(VolumeKeyInterceptor.self) private var interceptor

    @State private var hasAccessibilityPermission = VolumeKeyInterceptor.hasAccessibilityPermission
    @State private var permissionPollingTask: Task<Void, Never>?

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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "HA Volume Control")
                        .font(.headline)
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("Version \(version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Link("GitHub", destination: URL(string: "https://github.com/microcode/ha-volume-control/")!)
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Form {
                Section("Connection") {
                    TextField("URL", text: $haURL, prompt: Text("http://homeassistant.local:8123"))
                        .onChange(of: haURL) { _, new in
                            service.configure(url: new, token: haToken, entityID: service.entityID)
                        }
                }

                Section("Authentication") {
                    SecureField("Token", text: $haToken, prompt: Text("Long-lived access token"))
                        .onChange(of: haToken) { _, new in
                            KeychainHelper.save(new, forKey: "haToken")
                            service.configure(url: haURL, token: new, entityID: service.entityID)
                        }
                }

                Section("Volume Keys") {
                    Toggle("Intercept hardware volume keys", isOn: interceptorToggle)
                        .toggleStyle(.switch)
                        .tint(.accentColor)
                        .disabled(!hasAccessibilityPermission)
                    Text("Captures volume up/down keys system-wide and adjusts the media player instead. Requires Accessibility permission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !hasAccessibilityPermission {
                        Button("Grant Accessibility Permission") {
                            VolumeKeyInterceptor.requestAccessibilityPermission()
                        }
                        .font(.caption)
                    }
                    Toggle("Show percentage in volume HUD", isOn: $hudShowPercentage)
                        .toggleStyle(.switch)
                        .tint(.accentColor)
                }

                if !service.allLabels.isEmpty {
                    Section("Labels") {
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
                        }
                    }
                }

                if !service.integrations.isEmpty {
                    Section("Integrations") {
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
                                Label(integration.displayName, systemImage: integration.icon)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.bottom)
        }
        .frame(width: 450)
        .onAppear {
            haToken = KeychainHelper.load(forKey: "haToken")
            hasAccessibilityPermission = VolumeKeyInterceptor.hasAccessibilityPermission
            permissionPollingTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    hasAccessibilityPermission = VolumeKeyInterceptor.hasAccessibilityPermission
                }
            }
        }
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
        }
    }
}

#Preview {
    SettingsView()
}
