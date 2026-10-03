import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

enum ProviderChoice: String, AppEnum {
    case claude, gpt
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"
    static var caseDisplayRepresentations: [ProviderChoice: DisplayRepresentation] = [
        .claude: "Claude", .gpt: "ChatGPT",
    ]
}

enum MeterChoice: String, AppEnum {
    case claudeSession, claudeWeekly, claudeFable, gptSession, gptWeekly
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Meter"
    static var caseDisplayRepresentations: [MeterChoice: DisplayRepresentation] = [
        .claudeSession: "Claude · Session", .claudeWeekly: "Claude · Weekly", .claudeFable: "Claude · Fable",
        .gptSession: "ChatGPT · Session", .gptWeekly: "ChatGPT · Weekly",
    ]

    func meter(in s: Snapshot) -> Meter? {
        switch self {
        case .claudeSession: return s.meter("claude.session")
        case .claudeWeekly: return s.meter("claude.weekly")
        // The model-specific key may be named differently; fall back to the first extra Claude limit.
        case .claudeFable: return s.meter("claude.fable") ?? s.provider("claude")?.meters.dropFirst(2).first
        case .gptSession: return s.meter("gpt.session")
        case .gptWeekly: return s.meter("gpt.weekly")
        }
    }
}

struct ProviderIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Provider"
    static var description = IntentDescription("Choose which service to show.")
    @Parameter(title: "Provider", default: .claude) var provider: ProviderChoice
}

struct MeterIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Meter"
    static var description = IntentDescription("Choose which limit to show.")
    @Parameter(title: "Meter", default: .claudeSession) var meter: MeterChoice
}

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    var date: Date
    var snapshot: Snapshot
    var isSample: Bool
    var meter: MeterChoice = .claudeSession
    var provider: ProviderChoice = .claude

    func configured(_ intent: Any) -> UsageEntry {
        var e = self
        if let i = intent as? MeterIntent { e.meter = i.meter }
        if let i = intent as? ProviderIntent { e.provider = i.provider }
        return e
    }
}

private func currentEntry() -> UsageEntry {
    if let s = SnapshotStore.load() { return UsageEntry(date: .now, snapshot: s, isSample: false) }
    return UsageEntry(date: .now, snapshot: .sample, isSample: true)
}

private func timeline() -> Timeline<UsageEntry> {
    Timeline(entries: [currentEntry()], policy: .after(.now + 15 * 60))
}

struct IntentProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, snapshot: .sample, isSample: true) }
    func snapshot(for configuration: Intent, in context: Context) async -> UsageEntry {
        (context.isPreview ? placeholder(in: context) : currentEntry()).configured(configuration)
    }
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<UsageEntry> {
        Timeline(entries: [currentEntry().configured(configuration)], policy: .after(.now + 15 * 60))
    }
}

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: .now, snapshot: .sample, isSample: true) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) { completion(timeline()) }
}

// MARK: - Shared chrome

private struct Chrome: ViewModifier {
    var accent: Color
    var isSample: Bool
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isSample {
                    Text("Open AI Limits app").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.4)))
                }
            }
            .containerBackground(for: .widget) { WidgetBackdrop(accent: accent) }
    }
}

private extension View {
    func chrome(accent: Color, isSample: Bool) -> some View { modifier(Chrome(accent: accent, isSample: isSample)) }
}

private func providerFor(_ choice: ProviderChoice, in s: Snapshot) -> ProviderUsage {
    s.provider(choice.rawValue) ?? ProviderUsage(id: choice.rawValue, name: choice == .gpt ? "ChatGPT" : "Claude",
                                                 meters: [], error: "No data yet")
}

// MARK: - Dial (clock-style)

struct DialWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Dial", intent: MeterIntent.self, provider: IntentProvider<MeterIntent>()) { entry in
            DialView(entry: entry, choice: entry.meter)
        }
        .configurationDisplayName("Dial")
        .description("One limit as a big clock-style dial.")
        .supportedFamilies([.systemSmall])
    }
}

struct DialView: View {
    var entry: UsageEntry
    var choice: MeterChoice
    var body: some View {
        let meter = choice.meter(in: entry.snapshot)
        VStack(spacing: 4) {
            if let meter {
                TickDial(meter: meter)
                HStack(spacing: 4) {
                    Text(choice.rawValue.hasPrefix("gpt") ? "GPT" : "Claude").foregroundStyle(.secondary)
                    Text(meter.label).fontWeight(.semibold)
                    Text("· \(resetText(meter.resetsAt))").foregroundStyle(.tertiary)
                }
                .font(.system(size: 10))
                .lineLimit(1)
            } else {
                ProviderError(message: "No data for this limit yet")
            }
        }
        .chrome(accent: meter.map(Palette.tint) ?? .gray, isSample: entry.isSample)
    }
}

// MARK: - Rings (activity-style)

struct RingsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Rings", intent: ProviderIntent.self, provider: IntentProvider<ProviderIntent>()) { entry in
            RingsView(entry: entry, choice: entry.provider)
        }
        .configurationDisplayName("Rings")
        .description("Concentric rings for every limit.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RingsView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry
    var choice: ProviderChoice
    var body: some View {
        let p = providerFor(choice, in: entry.snapshot)
        Group {
            if family == .systemSmall {
                VStack(spacing: 8) {
                    ConcentricRings(meters: p.meters, lineWidth: 9, gap: 2.5)
                    HStack(spacing: 8) {
                        ForEach(p.meters) { m in
                            Text("\(Int(m.percent.rounded()))%")
                                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(Palette.tint(m))
                                .widgetAccentable()
                        }
                    }
                }
            } else {
                HStack(spacing: 14) {
                    ConcentricRings(meters: p.meters, lineWidth: 10, gap: 2.5)
                    VStack(alignment: .leading, spacing: 8) {
                        ProviderHeader(provider: p)
                        ForEach(p.meters) { MeterLegendRow(meter: $0) }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .chrome(accent: Palette.accent(for: p.id), isSample: entry.isSample)
    }
}

// MARK: - Bars

struct BarsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Bars", intent: ProviderIntent.self, provider: IntentProvider<ProviderIntent>()) { entry in
            BarsView(entry: entry, choice: entry.provider)
        }
        .configurationDisplayName("Bars")
        .description("Clean progress bars with reset times.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BarsView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry
    var choice: ProviderChoice
    var body: some View {
        let p = providerFor(choice, in: entry.snapshot)
        let compact = family == .systemSmall
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            ProviderHeader(provider: p)
            if let e = p.error, p.meters.isEmpty { ProviderError(message: e) }
            ForEach(p.meters) { MeterBarRow(meter: $0, compact: compact) }
            Spacer(minLength: 0)
        }
        .chrome(accent: Palette.accent(for: p.id), isSample: entry.isSample)
    }
}

// MARK: - Overview (everything)

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Overview", provider: StaticProvider()) { entry in
            OverviewView(entry: entry)
        }
        .configurationDisplayName("Overview")
        .description("Claude and ChatGPT limits side by side.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct OverviewView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry
    var body: some View {
        let providers = entry.snapshot.providers
        Group {
            if family == .systemLarge {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Divider().opacity(0.4).padding(.vertical, 12) }
                        ProviderTiles(provider: p, ring: 70, lineWidth: 7, spacing: 14)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Text("Updated \(entry.snapshot.updatedAt, style: .time)")
                            .font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            } else {
                // Medium: tiles for every meter, providers separated by a hairline.
                let total = max(providers.reduce(0) { $0 + max($1.meters.count, 1) }, 1)
                let ring: CGFloat = total >= 5 ? 40 : total == 4 ? 46 : 52
                HStack(alignment: .center, spacing: 12) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { VDivider() }
                        ProviderTiles(provider: p, ring: ring, lineWidth: 5, spacing: 6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .chrome(accent: Palette.accent(for: "claude"), isSample: entry.isSample)
    }
}

// MARK: - Bundle

@main
struct LimitsWidgets: WidgetBundle {
    var body: some Widget {
        DialWidget()
        RingsWidget()
        BarsWidget()
        OverviewWidget()
    }
}
