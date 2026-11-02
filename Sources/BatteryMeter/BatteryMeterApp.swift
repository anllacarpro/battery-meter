import SwiftUI
import BatteryCore

@main
struct BatteryMeterApp: App {
    // CLT ships no SwiftUIMacros plugin, so @State is unavailable; the App value lives
    // for the whole process, which makes a plain stored reference equivalent.
    private let model: BatteryModel

    init() {
        let model = BatteryModel()
        self.model = model
        if let dir = SnapshotRenderer.requestedDirectory {
            Task { await SnapshotRenderer.run(model: model, to: dir) }
        } else {
            model.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Battery Meter", id: "main") {
            Text("Overview")
        }
    }
}
