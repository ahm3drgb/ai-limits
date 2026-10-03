import SwiftUI

/// Black "island" fused with the MacBook notch: tiny gauges on each side, expands on hover.
@MainActor
final class NotchController {
    static let shared = NotchController()
    static let defaultsKey = "notch"
    static let meterKey = "notchMeter"   // "session" | "weekly" | "fable"

    private var panel: NSPanel?
    private var observer: Any?

    func update() {
        if UserDefaults.standard.bool(forKey: Self.defaultsKey) { show() } else { hide() }
    }

    private func show() {
        guard panel == nil, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        else { return }

        // Notch geometry; on screens without a notch, mimic one the height of the menu bar.
        let notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
        var notchWidth: CGFloat = 180
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - l.width - r.width
        }

        let size = CGSize(width: 760, height: notchHeight + 160)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView:
            NotchView(notchWidth: notchWidth, notchHeight: notchHeight)
                .environmentObject(UsageModel.shared)
                .frame(width: size.width, height: size.height, alignment: .top))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        // Re-place when displays change.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in NotchController.shared.hide(); NotchController.shared.update() }
        }
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}

private final class NotchPanel: NSPanel {
    // Allow sitting over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
}

struct NotchView: View {
    @EnvironmentObject var model: UsageModel
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    @AppStorage(NotchController.meterKey) private var meterKind = "session"
    @State private var expanded = false

    private let pillWidth: CGFloat = 66
    private let ear: CGFloat = 8   // concave flare where the island meets the menu bar

    var body: some View {
        let providers = model.snapshot.providers
        VStack(spacing: 0) {
            // Collapsed strip: one glance gauge each side of the physical notch.
            HStack(spacing: 0) {
                mini(glance(providers.first)).frame(width: pillWidth)
                Spacer().frame(width: notchWidth)
                mini(glance(providers.dropFirst().first)).frame(width: pillWidth)
            }
            .frame(height: notchHeight)

            if expanded {
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(providers.enumerated()), id: \.element.id) { i, p in
                            if i > 0 {
                                Rectangle().fill(.white.opacity(0.08)).frame(width: 1).padding(.vertical, 6)
                                    .padding(.horizontal, 14)
                            }
                            providerColumn(p)
                        }
                    }
                    HStack {
                        UpdatedFooter()
                        Spacer()
                        RefreshButton()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)).combined(with: .offset(y: -8)))
            }
        }
        .fixedSize(horizontal: expanded, vertical: false)
        .frame(minWidth: notchWidth + pillWidth * 2)
        .padding(.horizontal, ear)
        .background(NotchShape(ear: ear, bottomRadius: expanded ? 30 : 12).fill(.black))
        .shadow(color: .black.opacity(expanded ? 0.55 : 0), radius: 20, y: 8)
        .contentShape(NotchShape(ear: ear, bottomRadius: expanded ? 30 : 12))
        .onHover { hovering in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { expanded = hovering }
        }
        .preferredColorScheme(.dark)
    }

    private func providerColumn(_ p: ProviderUsage) -> some View {
        ProviderTiles(provider: p, ring: 58, lineWidth: 5.5, spacing: 12)
    }

    /// The meter chosen in settings, or the provider's first meter if it has none of that kind (e.g. ChatGPT has no Fable).
    private func glance(_ p: ProviderUsage?) -> Meter? {
        guard let p else { return nil }
        return p.meters.first { $0.id == "\(p.id).\(meterKind)" } ?? p.meters.first
    }

    @ViewBuilder
    private func mini(_ meter: Meter?) -> some View {
        if let meter {
            HStack(spacing: 5) {
                Ring(percent: meter.percent, color: Palette.tint(meter), lineWidth: 2.5).frame(width: 13, height: 13)
                Text("\(Int(meter.percent.rounded()))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
            }
            .opacity(expanded ? 0.6 : 1)
        } else {
            Color.clear
        }
    }
}

/// Notch silhouette: flat top that flares outward into the menu bar, rounded bottom corners.
struct NotchShape: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, e = ear
        let r = min(bottomRadius, (w - 2 * e) / 2, h - e)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: e, y: e), control: CGPoint(x: e, y: 0))
        p.addLine(to: CGPoint(x: e, y: h - r))
        p.addQuadCurve(to: CGPoint(x: e + r, y: h), control: CGPoint(x: e, y: h))
        p.addLine(to: CGPoint(x: w - e - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - e, y: h - r), control: CGPoint(x: w - e, y: h))
        p.addLine(to: CGPoint(x: w - e, y: e))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - e, y: 0))
        p.closeSubpath()
        return p
    }
}
