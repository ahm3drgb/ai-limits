import Foundation

struct Meter: Codable, Identifiable, Hashable {
    var id: String          // e.g. "claude.session"
    var label: String       // e.g. "Session"
    var percent: Double     // 0...100
    var resetsAt: Date?
}

struct ProviderUsage: Codable, Identifiable, Hashable {
    var id: String          // "claude" | "gpt"
    var name: String
    var meters: [Meter]
    var error: String?

    /// The provider-wide weekly limit, which the pace bar tracks.
    var weekly: Meter? { meters.first { $0.id == "\(id).weekly" } }
}

struct Snapshot: Codable, Hashable {
    var updatedAt: Date
    var providers: [ProviderUsage]

    func provider(_ id: String) -> ProviderUsage? { providers.first { $0.id == id } }
    func meter(_ id: String) -> Meter? { providers.flatMap(\.meters).first { $0.id == id } }

    static let sample = Snapshot(updatedAt: .now, providers: [
        ProviderUsage(id: "claude", name: "Claude", meters: [
            Meter(id: "claude.session", label: "Session", percent: 17, resetsAt: .now + 27 * 60),
            Meter(id: "claude.weekly", label: "Weekly", percent: 35, resetsAt: .now + 3 * 86400),
            Meter(id: "claude.fable", label: "Fable", percent: 18, resetsAt: .now + 3 * 86400),
        ]),
        ProviderUsage(id: "gpt", name: "ChatGPT", meters: [
            Meter(id: "gpt.session", label: "Session", percent: 42, resetsAt: .now + 2 * 3600),
            Meter(id: "gpt.weekly", label: "Weekly", percent: 61, resetsAt: .now + 4 * 86400),
        ]),
    ])
}

/// Snapshot file shared between the app (writer) and the sandboxed widget (reader).
/// The widget entitlement grants read-only access to this home-relative folder.
enum SnapshotStore {
    static var url: URL {
        // NSHomeDirectory() points into the container when sandboxed; use the real home.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/AILimits/snapshot.json")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}

func resetText(_ date: Date?, now: Date = .now) -> String {
    guard let date else { return "—" }
    let s = Int(date.timeIntervalSince(now))
    if s <= 0 { return "now" }
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(max(m, 1))m"
}

/// How weekly usage compares to an even spend of 100% / 7 days.
struct Pace: Hashable {
    enum Status: String {
        case coasting = "Coasting"       // barely touching the budget
        case healthy = "Healthy"         // under pace, room to spare
        case onPace = "On pace"          // spending about one day's share per day
        case runningHot = "Running hot"  // ahead of pace, will need to ease off
        case slowDown = "Slow down"      // far ahead, likely to hit the limit before reset
        case maxedOut = "Maxed out"
    }

    static let week: TimeInterval = 7 * 86400

    var used: Double        // 0...100
    var expected: Double    // where even spending would be by now, 0...100
    var daysAhead: Double   // (used - expected) in days of budget; negative = banked
    var perDayLeft: Double  // % per day you can spend from now until reset
    var runsOutIn: TimeInterval?  // at the current rate, only when that's before the reset
    var status: Status

    init(percent: Double, resetsAt: Date, now: Date = .now) {
        let left = min(max(resetsAt.timeIntervalSince(now), 0), Self.week)
        let elapsed = Self.week - left
        used = min(max(percent, 0), 100)
        expected = elapsed / Self.week * 100
        daysAhead = (used - expected) / (100 / 7)
        perDayLeft = left > 0 ? (100 - used) / (left / 86400) : 0
        if used > 0, elapsed > 0 {
            let toEmpty = (100 - used) / (used / elapsed)
            runsOutIn = toEmpty < left ? toEmpty : nil
        }
        status = used >= 100 ? .maxedOut
            : daysAhead >= 1.5 ? .slowDown
            : daysAhead >= 0.5 ? .runningHot
            : daysAhead > -0.5 ? .onPace
            : daysAhead > -1.5 ? .healthy
            : .coasting
    }

    /// Used vs. what an even 14.3%/day spend allows by now.
    var summary: String { "\(Int(used.rounded()))% used · \(Int(expected.rounded()))% allowed so far" }

    /// What to do about it: when it runs out if spending too fast, otherwise the daily allowance.
    func advice(resetsAt: Date) -> String {
        if status == .maxedOut { return "Limit reached · resets in \(resetText(resetsAt))" }
        if let runsOutIn, daysAhead >= 0.5 {
            return "At this rate you run out in \(resetText(.now + runsOutIn)), reset is in \(resetText(resetsAt))"
        }
        return "You can use \(Int(perDayLeft.rounded()))%/day until reset in \(resetText(resetsAt))"
    }
}

extension Meter {
    /// Pace against a 7-day window; nil for the short session window or when the reset is unknown.
    var pace: Pace? {
        guard !id.hasSuffix(".session"), let resetsAt else { return nil }
        return Pace(percent: percent, resetsAt: resetsAt)
    }
}
