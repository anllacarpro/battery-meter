import SwiftUI
import BatteryCore

@main
struct BatteryMeterApp: App {
    // CLT ships no SwiftUIMacros plugin, so @State is unavailable; the App value lives
    // for the whole process, which makes plain stored references equivalent.
    private let model: BatteryModel
    private let hover = ChartHover()

    init() {
        let model = BatteryModel()
        self.model = model
        #if DEBUG
        if let dir = SnapshotRenderer.requestedDirectory {
            Task { await SnapshotRenderer.run(model: model, to: dir) }
            return
        }
        #endif
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Battery Meter", id: "main") {
            MainWindow(model: model, hover: hover)
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
