import SwiftUI

// MARK: - Palette

enum Palette {
    static func color(for meterID: String) -> Color {
        switch meterID {
        case "claude.session": return Color(red: 1.00, green: 0.55, blue: 0.33)  // Claude coral
        case "claude.weekly":  return Color(red: 1.00, green: 0.78, blue: 0.36)  // amber
        case "gpt.session":    return Color(red: 0.25, green: 0.90, blue: 0.65)  // mint
        case "gpt.weekly":     return Color(red: 0.25, green: 0.70, blue: 1.00)  // sky
        default:               return Color(red: 0.70, green: 0.56, blue: 1.00)  // Fable / other model limits: violet
        }
    }

    static func accent(for providerID: String) -> Color {
        providerID == "gpt" ? color(for: "gpt.session") : color(for: "claude.session")
    }

    static func tint(_ meter: Meter) -> Color {
        meter.percent >= 90 ? Color(red: 1.0, green: 0.33, blue: 0.36) : color(for: meter.id)
    }

    static func color(for status: Pace.Status) -> Color {
        switch status {
        case .coasting:   return Color(red: 0.40, green: 0.78, blue: 1.00)  // calm blue
        case .healthy:    return Color(red: 0.30, green: 0.88, blue: 0.55)  // green
        case .onPace:     return Color(red: 0.78, green: 0.90, blue: 0.35)  // lime
        case .runningHot: return Color(red: 1.00, green: 0.66, blue: 0.25)  // orange
        case .slowDown, .maxedOut: return Color(red: 1.00, green: 0.33, blue: 0.36)  // red
        }
    }
}

// MARK: - Ring

struct Ring: View {
    var percent: Double
    var color: Color
    var lineWidth: CGFloat

    var body: some View {
        let p = min(max(percent / 100, 0), 1)
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(p, 0.001))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                    startAngle: .zero, endAngle: .degrees(360 * p)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: lineWidth / 3)
                .widgetAccentable()
        }
    }
}

/// Activity-style concentric rings, outermost = first meter.
struct ConcentricRings: View {
    var meters: [Meter]
    var lineWidth: CGFloat = 9
    var gap: CGFloat = 3

    var body: some View {
        ZStack {
            ForEach(Array(meters.enumerated()), id: \.element.id) { i, m in
                Ring(percent: m.percent, color: Palette.tint(m), lineWidth: lineWidth)
                    .padding(CGFloat(i) * (lineWidth + gap) + lineWidth / 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Clock-face dial: tick marks around the edge light up with usage, big number in the middle.
struct TickDial: View {
    var meter: Meter
    var ticks = 48

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lit = Int((min(max(meter.percent, 0), 100) / 100 * Double(ticks)).rounded())
            let color = Palette.tint(meter)
            ZStack {
                ForEach(0..<ticks, id: \.self) { i in
                    Capsule()
                        .fill(i < lit ? color : Color.primary.opacity(0.18))
                        .frame(width: size * 0.018, height: i % 4 == 0 ? size * 0.07 : size * 0.045)
                        .offset(y: -size / 2 + size * 0.05)
                        .rotationEffect(.degrees(Double(i) / Double(ticks) * 360))
                        .widgetAccentable(i < lit)
                }
                (Text("\(Int(meter.percent.rounded()))")
                    .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                 + Text("%").font(.system(size: size * 0.15, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct Bar: View {
    var meter: Meter
    var height: CGFloat = 6

    var body: some View {
        let color = Palette.tint(meter)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(max(meter.percent / 100, 0), 1)))
                    .shadow(color: color.opacity(0.5), radius: height / 2)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

/// Weekly health: seven day-sized cells filled by usage, a faint glow for what's still available today,
/// and a tick where even spending should be by midnight.
struct PaceBar: View {
    var title: String
    var meter: Meter
    var pace: Pace
    var height: CGFloat = 6

    var body: some View {
        let color = Palette.color(for: pace.status)
        VStack(alignment: .leading, spacing: 8) {  // room for the tick, which overhangs the bar by 3pt
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 3).widgetAccentable()
                Text(pace.status.rawValue).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                Spacer(minLength: 6)
                Text(pace.summary).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
            }
            .lineLimit(1)
            GeometryReader { geo in
                let gap: CGFloat = 2
                let cell = (geo.size.width - gap * 6) / 7
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { day in
                            let fill = min(max(pace.used / (100 / 7) - Double(day), 0), 1)
                            let today = min(max(pace.todayTarget / (100 / 7) - Double(day), 0), 1)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule().fill(color.opacity(0.3)).frame(width: cell * today)
                                Capsule().fill(color).frame(width: cell * fill).widgetAccentable()
                            }
                            .frame(width: cell)
                        }
                    }
                    .shadow(color: color.opacity(0.4), radius: height / 2)
                    Capsule().fill(Color.primary.opacity(0.95))
                        .frame(width: 2, height: height + 6)
                        .shadow(color: .black, radius: 1)
                        .offset(x: min(max(geo.size.width * pace.todayTarget / 100 - 1, 0), geo.size.width - 2))
                        .help("On pace by midnight: \(Int(pace.todayTarget.rounded()))%")
                }
            }
            .frame(height: height)
            if let resetsAt = meter.resetsAt {
                Text(pace.advice(resetsAt: resetsAt))
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

// MARK: - Rows / legends

struct MeterLegendRow: View {
    var meter: Meter
    var showReset = true

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Palette.tint(meter)).frame(width: 7, height: 7).widgetAccentable()
            Text(meter.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            if showReset {
                Text(resetText(meter.resetsAt)).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Text("\(Int(meter.percent.rounded()))%")
                .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
        }
    }
}

struct MeterBarRow: View {
    var meter: Meter
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(meter.label).font(.system(size: compact ? 11 : 13, weight: .semibold))
                Spacer()
                if compact {
                    Text(resetText(meter.resetsAt)).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Text("\(Int(meter.percent.rounded()))%")
                    .font(.system(size: compact ? 12 : 15, weight: .bold, design: .rounded)).monospacedDigit()
            }
            Bar(meter: meter, height: compact ? 5 : 7)
            if !compact {
                Text("Resets in \(resetText(meter.resetsAt))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProviderHeader: View {
    var provider: ProviderUsage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: provider.id == "gpt" ? "circle.hexagongrid.fill" : "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.accent(for: provider.id))
                .widgetAccentable()
            Text(provider.name.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
        }
    }
}

struct ProviderError: View {
    var message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
    }
}

/// Rings on the left, legend on the right.
struct ProviderRingsCard: View {
    var provider: ProviderUsage
    var lineWidth: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderHeader(provider: provider)
            if let error = provider.error, provider.meters.isEmpty {
                ProviderError(message: error)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 10) {
                    ConcentricRings(meters: provider.meters, lineWidth: lineWidth)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(provider.meters) { MeterLegendRow(meter: $0, showReset: false) }
                    }
                }
            }
        }
    }
}

// MARK: - Background

struct WidgetBackdrop: View {
    var accent: Color = Palette.color(for: "claude.session")
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.12), Color(red: 0.03, green: 0.03, blue: 0.06)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
        }
    }
}

// MARK: - Tiles

/// One limit: ring with the percentage inside, label and reset time underneath.
struct MeterTile: View {
    var meter: Meter
    var ring: CGFloat = 56
    var lineWidth: CGFloat = 5.5

    var body: some View {
        let color = Palette.tint(meter)
        VStack(spacing: ring * 0.09) {
            ZStack {
                Ring(percent: meter.percent, color: color, lineWidth: lineWidth)
                (Text("\(Int(meter.percent.rounded()))")
                    .font(.system(size: ring * 0.3, weight: .bold, design: .rounded)).monospacedDigit()
                 + Text("%").font(.system(size: ring * 0.16, weight: .bold, design: .rounded)).foregroundColor(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(lineWidth + 2)
            }
            .frame(width: ring, height: ring)
            VStack(spacing: 1) {
                Text(meter.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
                    .widgetAccentable()
                Text(resetText(meter.resetsAt)).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.tertiary)
            }
            .lineLimit(1)
        }
        .frame(width: ring + 10)
    }
}

/// Provider header with a row of meter tiles.
struct ProviderTiles: View {
    var provider: ProviderUsage
    var ring: CGFloat = 56
    var lineWidth: CGFloat = 5.5
    var spacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderHeader(provider: provider)
            if let e = provider.error, provider.meters.isEmpty {
                ProviderError(message: e)
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(provider.meters) { MeterTile(meter: $0, ring: ring, lineWidth: lineWidth) }
                }
            }
        }
    }
}

struct VDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1).padding(.vertical, 4)
    }
}
