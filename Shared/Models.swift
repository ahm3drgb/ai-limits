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
