import SwiftUI
import WidgetKit

@main
struct AILimitsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var model = UsageModel.shared
    @AppStorage(UsageModel.menuBarMeterKey) private var menuBarMeter = "claude.session"

    var body: some Scene {
        // Menu bar icon; click opens the glass dashboard.
        MenuBarExtra {
            MenuPanel().environmentObject(model)
        } label: {
            let pct = model.snapshot.meter(menuBarMeter).map { " \(Int($0.percent.rounded()))%" } ?? ""
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(pct)
        }
        .menuBarExtraStyle(.window)

        // Optional pop-out window: resizable, can be pinned on top.
        Window("AI Limits", id: "main") {
            MainView().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 380, height: 500)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh") { Task { await model.refresh() } }.keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotchController.shared.update()
    }
}

@MainActor
final class UsageModel: ObservableObject {
    static let shared = UsageModel()

    @Published var snapshot: Snapshot = SnapshotStore.load() ?? Snapshot(updatedAt: .distantPast, providers: [])
    @Published var isLoading = false
    private var timer: Timer?

    static let menuBarMeterKey = "menuBarMeter"
    static let refreshKey = "refreshMinutes"

    private init() {
        Task { await refresh() }
        scheduleRefresh()
    }

    /// (Re)starts the auto-refresh timer using the interval from settings.
    func scheduleRefresh() {
        let minutes = UserDefaults.standard.object(forKey: Self.refreshKey) as? Int ?? 2
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(minutes, 1) * 60), repeats: true) { _ in
            Task { await UsageModel.shared.refresh() }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let fresh = await Fetchers.fetchAll()
        snapshot = fresh
        try? SnapshotStore.save(fresh)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
