import SwiftUI

enum DisplayStyle: String, CaseIterable, Identifiable {
    case rings = "Rings", bars = "Bars", dials = "Dials"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .rings: return "circle.circle"
        case .bars: return "chart.bar.fill"
        case .dials: return "gauge.open.with.lines.needle.33percent"
        }
    }
}

// MARK: - Dashboard (shared by popover and window)

struct Dashboard: View {
    @EnvironmentObject var model: UsageModel
    var style: DisplayStyle
    var width: CGFloat
    var compact = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.snapshot.providers) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        ProviderHeader(provider: p)
                        if let e = p.error, p.meters.isEmpty { ProviderError(message: e) }
                        ForEach(p.meters) { MeterBarRow(meter: $0, compact: true) }
                    }
                }
            }
        } else {
            VStack(spacing: 12) {
                if model.snapshot.providers.isEmpty {
                    ProgressView().controlSize(.small).padding(30)
                }
                ForEach(model.snapshot.providers) { p in
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            ProviderHeader(provider: p)
                            if let e = p.error, p.meters.isEmpty {
                                ProviderError(message: e)
                            } else {
                                switch style {
                                case .rings: rings(p)
                                case .bars: VStack(spacing: 14) { ForEach(p.meters) { MeterBarRow(meter: $0) } }
                                case .dials: dials(p)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func rings(_ p: ProviderUsage) -> some View {
        HStack(spacing: 18) {
            ConcentricRings(meters: p.meters, lineWidth: 11, gap: 3)
                .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(p.meters) { m in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Circle().fill(Palette.tint(m)).frame(width: 8, height: 8)
                            Text(m.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(m.percent.rounded()))%")
                                .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                        Text("resets in \(resetText(m.resetsAt))").font(.system(size: 10)).foregroundStyle(.tertiary)
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func dials(_ p: ProviderUsage) -> some View {
        let count = max(2, min(p.meters.count, Int(width / 110)))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: count), spacing: 10) {
            ForEach(p.meters) { m in
                VStack(spacing: 4) {
                    TickDial(meter: m).frame(height: 84)
                    Text(m.label).font(.system(size: 11, weight: .semibold))
                    Text(resetText(m.resetsAt)).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Shared controls

struct StylePicker: View {
    @Binding var style: DisplayStyle
    var body: some View {
        Picker("Style", selection: $style) {
            ForEach(DisplayStyle.allCases) { Image(systemName: $0.icon).tag($0).help($0.rawValue) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 110)
    }
}

struct IconButton: View {
    var name: String
    var help: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Palette.color(for: "claude.session") : .secondary)
        .help(help)
    }
}

struct RefreshButton: View {
    @EnvironmentObject var model: UsageModel
    var body: some View {
        IconButton(name: "arrow.clockwise", help: "Refresh") { Task { await model.refresh() } }
            .rotationEffect(.degrees(model.isLoading ? 360 : 0))
            .animation(model.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                       value: model.isLoading)
    }
}

struct UpdatedFooter: View {
    @EnvironmentObject var model: UsageModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Text(model.snapshot.updatedAt == .distantPast ? "Loading…" :
                    "Updated \(model.snapshot.updatedAt.formatted(.relative(presentation: .named)))")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Menu bar popover

struct MenuPanel: View {
    @EnvironmentObject var model: UsageModel
    @AppStorage("style") private var style: DisplayStyle = .rings
    @AppStorage(NotchController.defaultsKey) private var notch = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("AI Limits").font(.system(size: 14, weight: .bold))
                Spacer()
                StylePicker(style: $style)
                RefreshButton()
            }
            Dashboard(style: style, width: 340)
            HStack(spacing: 4) {
                UpdatedFooter()
                Spacer()
                IconButton(name: "rectangle.topthird.inset.filled", help: "Show in notch", active: notch) {
                    notch.toggle()
                    NotchController.shared.update()
                }
                IconButton(name: "macwindow.on.rectangle", help: "Open floating window") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                IconButton(name: "power", help: "Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Pop-out window

struct MainView: View {
    @EnvironmentObject var model: UsageModel
    @AppStorage("style") private var style: DisplayStyle = .rings
    @AppStorage("pinned") private var pinned = true

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 300 || geo.size.height < 300
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Spacer()
                    if !compact { StylePicker(style: $style) }
                    IconButton(name: pinned ? "pin.fill" : "pin", help: pinned ? "Unpin" : "Keep on top",
                               active: pinned) { pinned.toggle() }
                    RefreshButton()
                }
                .padding(.leading, 76)   // clear the traffic lights
                .padding(.trailing, 12)
                .frame(height: 30)
                ScrollView(showsIndicators: false) {
                    Dashboard(style: style, width: geo.size.width, compact: compact)
                        .padding(.horizontal, compact ? 12 : 16)
                        .padding(.bottom, 12)
                }
                if !compact { UpdatedFooter().padding(.bottom, 8) }
            }
        }
        .frame(minWidth: 200, minHeight: 130)
        .background(Backdrop().ignoresSafeArea())
        .background(WindowAccessor { window in
            window.level = pinned ? .floating : .normal
            window.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
            window.isMovableByWindowBackground = true
        }.id(pinned))
        .preferredColorScheme(.dark)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

/// Frosted glass window background.
struct Backdrop: View {
    var body: some View {
        ZStack {
            VisualEffect()
            LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.16).opacity(0.65),
                                    Color(red: 0.03, green: 0.03, blue: 0.07).opacity(0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Palette.color(for: "claude.session").opacity(0.18), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 320)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Hands the hosting NSWindow to a closure once the view is in a window.
struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { configure(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { configure(w) } }
    }
}
