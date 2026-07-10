import AppKit
import CoreGraphics
import Observation

// Constants from <IOKit/hidsystem/ev_keymap.h>

private enum NXKeyType {
    static let soundUp = 0 // NX_KEYTYPE_SOUND_UP
    static let soundDown = 1 // NX_KEYTYPE_SOUND_DOWN
    static let mute = 7 // NX_KEYTYPE_MUTE
}

private enum NXKeyState {
    static let stateDown = 0x0A // NX_KEYSTATE_DOWN
}

private enum NXKeySubType {
    static let auxControlButtons = 8 // NX_SUBTYPE_AUX_CONTROL_BUTTONS
}

@Observable
final class VolumeKeyInterceptor {
    var isEnabled: Bool = false
    let step: Double = 0.05

    // Weak so the interceptor doesn't extend the service's lifetime
    weak var service: HAService?
    var hud: VolumeHUDPanel?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Retained pointer passed to the C callback so self stays alive
    private var tapRetain: Unmanaged<VolumeKeyInterceptor>?

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func enable() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard eventTap == nil else { return true }

        let retained = Unmanaged.passRetained(self)
        let mask = CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: volumeKeyEventCallback,
            userInfo: retained.toOpaque()
        ) else {
            retained.release()
            return false
        }

        tapRetain = retained
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isEnabled = true
        return true
    }

    func disable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        tapRetain?.release()
        tapRetain = nil
        isEnabled = false
    }

    fileprivate func handleVolumeKey(isUp: Bool) {
        guard let service else { return }
        let newVolume = isUp
            ? min(1.0, service.volume + step)
            : max(0.0, service.volume - step)
        service.volume = newVolume
        Task { await service.setVolume(newVolume) }
        hud?.show(volume: newVolume, isMuted: service.isMuted, deviceName: service.friendlyName)
    }

    fileprivate func handleMuteKey() {
        guard let service else { return }
        let predictedMuted = !service.isMuted
        Task { await service.toggleMute() }
        hud?.show(volume: service.volume, isMuted: predictedMuted, deviceName: service.friendlyName)
    }

    deinit { disable() }
}

/// File-scope function required for @convention(c) callback — cannot capture context
private func volumeKeyEventCallback(
    proxy _: CGEventTapProxy,
    type _: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon,
          let nsEvent = NSEvent(cgEvent: event),
          nsEvent.type == .systemDefined,
          nsEvent.subtype.rawValue == NXKeySubType.auxControlButtons
    else {
        return Unmanaged.passRetained(event)
    }

    // data1 packs the key code in the high 16 bits and flags in the low 16 bits;
    // the high byte of the flags holds the key state.
    let keyCode = Int((nsEvent.data1 & 0xFFFF_0000) >> 16)
    let keyFlags = nsEvent.data1 & 0x0000_FFFF
    let isKeyDown = ((keyFlags & 0xFF00) >> 8) == NXKeyState.stateDown

    guard keyCode == NXKeyType.soundUp || keyCode == NXKeyType.soundDown || keyCode == NXKeyType.mute else {
        return Unmanaged.passRetained(event) // pass other media keys through
    }

    if isKeyDown {
        let interceptor = Unmanaged<VolumeKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
        if keyCode == NXKeyType.mute {
            interceptor.handleMuteKey()
        } else {
            interceptor.handleVolumeKey(isUp: keyCode == NXKeyType.soundUp)
        }
    }

    return nil // consume key-down and key-up for all intercepted media keys
}
