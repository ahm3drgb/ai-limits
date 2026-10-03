import SwiftUI

/// Popover tab that previews the desktop widgets with live data and explains how to add them.
struct WidgetsTab: View {
    @EnvironmentObject var model: UsageModel

    var body: some View {
        let s = model.snapshot.providers.isEmpty ? Snapshot.sample : model.snapshot
        let claude = s.provider("claude") ?? Snapshot.sample.providers[0]
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let m = s.meter("claude.session") {
                    WidgetPreview(title: "Dial") { TickDial(meter: m) }
                }
                WidgetPreview(title: "Rings") { ConcentricRings(meters: claude.meters, lineWidth: 6, gap: 2) }
                WidgetPreview(title: "Bars") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(claude.meters) { m in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.label).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                                Bar(meter: m, height: 4)
                            }
                        }
                    }
                }
            }
            WidgetPreview(title: "Overview", width: 312) {
                HStack(spacing: 10) {
                    ForEach(Array(s.providers.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { VDivider() }
                        HStack(spacing: 4) {
                            ForEach(p.meters) { MeterTile(meter: $0, ring: 34, lineWidth: 3.5) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Add to your desktop").font(.system(size: 12, weight: .semibold))
                step(1, "Right-click an empty spot on the desktop.")
                step(2, "Choose **Edit Widgets…**")
                step(3, "Search **AI Limits** and drag a widget out.")
                step(4, "Right-click a widget, then **Edit** to pick Claude or ChatGPT, or the limit to show.")
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 16, height: 16)
                .background(Circle().fill(.white.opacity(0.1)))
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Scaled-down widget frame with the widget's own backdrop and its name underneath.
private struct WidgetPreview<Content: View>: View {
    var title: String
    var width: CGFloat = 97
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 5) {
            content
                .padding(10)
                .frame(width: width, height: 97)
                .background(WidgetBackdrop())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.08)))
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}
