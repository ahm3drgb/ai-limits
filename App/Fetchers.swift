import Foundation

/// Reads usage from the same private endpoints Claude Code and Codex CLI use for their
/// own usage screens. Both are undocumented and may change; failures surface as `error`.
enum Fetchers {
    static func fetchAll() async -> Snapshot {
        async let claude = Self.claude()
        async let gpt = Self.gpt()
        return Snapshot(updatedAt: .now, providers: [await claude, await gpt])
    }

    // MARK: Claude (Claude Code OAuth login)

    static func claude() async -> ProviderUsage {
        var usage = ProviderUsage(id: "claude", name: "Claude", meters: [])
        do {
            let token = try claudeToken()
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            let json = try await getJSON(req)
            usage.meters = parseClaudeLimits(json["limits"] as? [[String: Any]] ?? [])
            if usage.meters.isEmpty { usage.meters = parseClaudeLegacy(json) }
            if usage.meters.isEmpty { usage.error = "No usage data returned" }
        } catch {
            usage.error = error.localizedDescription
        }
        return usage
    }

    /// Current format: a `limits` array with session, weekly and per-model ("weekly_scoped") entries.
    private static func parseClaudeLimits(_ limits: [[String: Any]]) -> [Meter] {
        limits.compactMap { l in
            guard let pct = (l["percent"] as? NSNumber)?.doubleValue else { return nil }
            let reset = parseISO(l["resets_at"] as? String)
            switch l["kind"] as? String {
            case "session":
                return Meter(id: "claude.session", label: "Session", percent: pct, resetsAt: reset)
            case "weekly_all":
                return Meter(id: "claude.weekly", label: "Weekly", percent: pct, resetsAt: reset)
            case "weekly_scoped":
                let scope = l["scope"] as? [String: Any]
                let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
                    ?? (scope?["surface"] as? [String: Any])?["display_name"] as? String
                    ?? "Model"
                return Meter(id: "claude.\(model.lowercased())", label: model, percent: pct, resetsAt: reset)
            default:
                return nil
            }
        }
    }

    /// Older format: top-level `five_hour`, `seven_day`, `seven_day_<model>` objects.
    private static func parseClaudeLegacy(_ json: [String: Any]) -> [Meter] {
        func meter(_ key: String, id: String, label: String) -> Meter? {
            guard let d = json[key] as? [String: Any],
                  let u = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return Meter(id: id, label: label, percent: u, resetsAt: parseISO(d["resets_at"] as? String))
        }
        var meters = [meter("five_hour", id: "claude.session", label: "Session"),
                      meter("seven_day", id: "claude.weekly", label: "Weekly")].compactMap { $0 }
        for key in json.keys.sorted() where key.hasPrefix("seven_day_") && !key.contains("oauth") {
            let model = String(key.dropFirst("seven_day_".count))
            if let m = meter(key, id: "claude.\(model)", label: model.capitalized) { meters.append(m) }
        }
        return meters
    }

    private static func claudeToken() throws -> String {
        // Claude Code stores its login in the login keychain. Using /usr/bin/security (the same
        // tool that wrote it) avoids a new keychain prompt after every rebuild of this app.
        var raw = try? run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        if raw == nil || raw!.isEmpty {
            let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
            raw = (try? String(contentsOf: file, encoding: .utf8))
        }
        guard let data = raw?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw FetchError("Sign in to Claude Code first") }
        if let exp = (oauth["expiresAt"] as? NSNumber)?.doubleValue, exp / 1000 < Date().timeIntervalSince1970 {
            throw FetchError("Login expired – open Claude Code to refresh")
        }
        return token
    }

    // MARK: ChatGPT (Codex CLI login)

    static func gpt() async -> ProviderUsage {
        var usage = ProviderUsage(id: "gpt", name: "ChatGPT", meters: [])
        do {
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            guard let data = try? Data(contentsOf: codexHome.appendingPathComponent("auth.json")),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = obj["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String
            else { throw FetchError("Sign in to Codex CLI first") }

            var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let account = tokens["account_id"] as? String {
                req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
            }
            let json = try await getJSON(req)
            let limits = json["rate_limit"] as? [String: Any] ?? [:]

            // Plans expose a short (5h) and/or weekly window; label each by its length, not its slot.
            func meter(_ key: String) -> Meter? {
                guard let w = limits[key] as? [String: Any],
                      let used = (w["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                var reset: Date?
                if let at = (w["reset_at"] as? NSNumber)?.doubleValue { reset = Date(timeIntervalSince1970: at) }
                else if let after = (w["reset_after_seconds"] as? NSNumber)?.doubleValue { reset = .now + after }
                let weekly = ((w["limit_window_seconds"] as? NSNumber)?.intValue ?? 0) >= 86400
                return Meter(id: weekly ? "gpt.weekly" : "gpt.session", label: weekly ? "Weekly" : "Session",
                             percent: used, resetsAt: reset)
            }
            usage.meters = ["primary_window", "secondary_window"].compactMap(meter)
                .sorted { $0.id == "gpt.session" && $1.id != "gpt.session" }
            if usage.meters.isEmpty { usage.error = "No usage data returned" }
        } catch {
            usage.error = error.localizedDescription
        }
        return usage
    }

    // MARK: Helpers

    private static func getJSON(_ req: URLRequest) async throws -> [String: Any] {
        var req = req
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw FetchError("Not authorized (\(status)) – sign in again") }
        guard (200..<300).contains(status) else { throw FetchError("Server error \(status)") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FetchError("Unexpected response")
        }
        return obj
    }

    private static func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw FetchError("\(path) failed") }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        // Fall back for microsecond precision or no fraction: drop the fractional part.
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: trimmed)
    }
}

struct FetchError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
