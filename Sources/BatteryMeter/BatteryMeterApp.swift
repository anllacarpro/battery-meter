import SwiftUI
import BatteryCore

@main
struct BatteryMeterApp: App {
    // CLT ships no SwiftUIMacros plugin, so @State is unavailable; the App value lives
    // for the whole process, which makes plain stored references equivalent.
    private let model: BatteryModel
    private let hover = ChartHover()
    private let settings = SettingsState()
    private let reports: ReportsModel
    private let sampler: EnergySampler

    init() {
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
            Task { await SnapshotRenderer.run(model: model, reports: reports, to: dir) }
            return
        }
        #endif
        settings.offerLaunchAtLoginOnce()
        model.start()
        sampler.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Battery Meter", id: "main") {
            MainWindow(model: model, reports: reports, hover: hover, settings: settings)
                // Menu bar only, except while this window is open.
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .defaultSize(width: 760, height: 520)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
