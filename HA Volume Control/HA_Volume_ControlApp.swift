import Sparkle
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
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @State private var service: HAService
    @State private var interceptor: VolumeKeyInterceptor
    @State private var audioDeviceMonitor: AudioDeviceMonitor

    init() {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1
        {
            exit(0)
        }

        let service = HAService()
        let interceptor = VolumeKeyInterceptor()
        let monitor = AudioDeviceMonitor()
        interceptor.service = service
        interceptor.hud = VolumeHUDPanel()
        interceptor.audioDeviceMonitor = monitor
        _service = State(initialValue: service)
        _interceptor = State(initialValue: interceptor)
        _audioDeviceMonitor = State(initialValue: monitor)

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

        if defaults.bool(forKey: "restrictToOutputDevice") {
            let uid = defaults.string(forKey: "requiredOutputDeviceUID") ?? ""
            interceptor.requiredOutputDeviceUID = uid.isEmpty ? nil : uid
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
            SettingsView(updater: updaterController.updater)
                .environment(service)
                .environment(interceptor)
                .environment(audioDeviceMonitor)
        }
        .windowResizability(.contentSize)
    }
}
