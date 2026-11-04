import AppKit
import BatteryCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hover = ChartHover()
    private let settings = SettingsState()
    private var model: BatteryModel?
    private var reports: ReportsModel?
    private var sampler: EnergySampler?
    // Both live as long as the app.
    private var windowController: MainWindowController?
    private var statusItemController: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A directly run binary has no LSUIElement key, so without this it would show a
        // Dock icon. The main window switches to .regular while it's open.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(openSettings(_:)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let energyStore = AppEnergyStore(fileURL: AppEnergyStore.defaultURL)
        let model = BatteryModel(energyStore: energyStore)
        let reports = ReportsModel(battery: model, energyStore: energyStore, logSource: PowerLogSource())
        let sampler = EnergySampler(battery: model, store: energyStore)
        // Reset clears the history and app-energy files (BatteryModel), then the report
        // and any in-flight sample.
        model.onReset = { [weak reports, weak sampler] in
            reports?.handleReset()
            sampler?.handleReset()
        }
        // A report built before the history loads would be empty, so `refresh` waits for
        // it; each new history window (launch load, retention change) forces a rebuild.
        model.onHistoryLoaded = { [weak reports] in
            reports?.refresh(force: true)
        }
        self.model = model
        self.reports = reports
        self.sampler = sampler
        #if DEBUG
        if let dir = SnapshotRenderer.requestedDirectory {
            // No status item, sampling or window: render and exit.
            Task { await SnapshotRenderer.run(model: model, reports: reports, sampler: sampler, to: dir) }
            return
        }
        #endif
        settings.offerLaunchAtLoginOnce()
        settings.updates.checkIfDue()
        let window = MainWindowController(model: model, reports: reports, hover: hover, settings: settings)
        windowController = window
        statusItemController = StatusItemController(model: model, sampler: sampler, settings: settings, window: window)
        model.start()
        sampler.start()
    }

    /// The status item lives on after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Launching the app again (Finder, Spotlight) opens the window: the menu bar item may
    /// be hidden by macOS when the menu bar is full.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show(pane: nil)
        return true
    }

    @objc private func openSettings(_ sender: Any?) {
        windowController?.show(pane: .settings)
    }
}
