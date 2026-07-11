import SwiftUI

private struct MenuBarIcon: View {
    @Environment(HAService.self) private var service

    var body: some View {
        Image(systemName: iconName)
            .opacity(service.isConnected ? 1.0 : 0.4)
    }

    private var iconName: String {
        if service.isMuted || service.volume == 0 {
            return "speaker.slash"
        }
        if service.volume <= 0.33 {
            return "speaker.wave.1"
        }
        if service.volume <= 0.66 {
            return "speaker.wave.2"
        }
        return "speaker.wave.3"
    }
}

@main
struct HA_Volume_ControlApp: App {
    @State private var service: HAService
    @State private var interceptor: VolumeKeyInterceptor

    init() {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            exit(0)
        }

        let service = HAService()
        let interceptor = VolumeKeyInterceptor()
        interceptor.service = service
        interceptor.hud = VolumeHUDPanel()
        _service = State(initialValue: service)
        _interceptor = State(initialValue: interceptor)

        KeychainHelper.migrateTokenIfNeeded()

        let defaults = UserDefaults.standard
        service.configure(
            url: defaults.string(forKey: "haURL") ?? "",
            token: KeychainHelper.load(forKey: "haToken"),
            entityID: defaults.string(forKey: "haEntityID") ?? ""
        )
        Task { await service.fetchVolume() }

        if defaults.bool(forKey: "interceptVolumeKeys") {
            _ = interceptor.enable()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(service)
                .environment(interceptor)
        } label: {
            MenuBarIcon()
                .environment(service)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(service)
                .environment(interceptor)
        }
    }
}
