import AppKit
import SwiftUI

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        // .fullScreenUI is the most transparent standard material — barely tinted,
        // so the Liquid Glass layer above provides most of the appearance.
        view.material = .fullScreenUI
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct HUDBackground: ViewModifier {
    private static let cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.clear, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        } else {
            content.background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }
}

private struct HUDView: View {
    let volume: Double
    let isMuted: Bool
    let deviceName: String

    @AppStorage("hudShowPercentage") private var showPercentage = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            if !deviceName.isEmpty {
                Text(deviceName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .frame(width: 16)

                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.15))
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                                .frame(width: max(0, geo.size.width * (isMuted ? 0 : volume)))
                        }
                    }
                    .frame(height: 4)

                    HStack(spacing: 0) {
                        ForEach(0 ... 10, id: \.self) { i in
                            if i > 0 {
                                Spacer(minLength: 0)
                            }
                            Rectangle()
                                .fill(Color.primary.opacity(0.15))
                                .frame(width: 1, height: 2)
                        }
                    }
                }

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .frame(width: 16)

                if showPercentage {
                    Text("\(Int(((isMuted ? 0 : volume) * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .modifier(HUDBackground())
        .frame(width: 300)
    }
}

final class VolumeHUDPanel {
    private let panel: NSPanel
    private let hostingView: NSHostingView<HUDView>
    private var hideWorkItem: DispatchWorkItem?
    private var iconCenterX: CGFloat

    func noteIconCenter(_ x: CGFloat) {
        iconCenterX = x
        UserDefaults.standard.set(x, forKey: "hudIconCenterX")
    }

    init() {
        iconCenterX = UserDefaults.standard.double(forKey: "hudIconCenterX")
        hostingView = NSHostingView(rootView: HUDView(volume: 0.5, isMuted: false, deviceName: ""))

        let size = hostingView.fittingSize
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hostingView
        panel.alphaValue = 0
    }

    func show(volume: Double, isMuted: Bool, deviceName: String) {
        let screen = NSScreen.screens[0]
        let isPopupVisible = NSApp.windows.contains { window in
            window is NSPanel &&
                window.level != .screenSaver &&
                window.isVisible &&
                abs(window.frame.maxY - screen.visibleFrame.maxY) < 50
        }
        guard !isPopupVisible else { return }

        hideWorkItem?.cancel()
        hideWorkItem = nil

        hostingView.rootView = HUDView(volume: volume, isMuted: isMuted, deviceName: deviceName)

        let centerX = iconCenterX > 0 ? iconCenterX : screen.frame.midX
        let size = hostingView.fittingSize
        let x = max(0, min(centerX - size.width / 2, screen.frame.maxX - size.width))
        let y = screen.visibleFrame.maxY - size.height - 10
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)

        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                if (self?.panel.alphaValue ?? 0) < 0.05 {
                    self?.panel.orderOut(nil)
                }
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }
}
