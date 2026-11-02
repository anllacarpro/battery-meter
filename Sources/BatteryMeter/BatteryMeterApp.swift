import SwiftUI
import BatteryCore

@main
struct BatteryMeterApp: App {
    var body: some Scene {
        MenuBarExtra("Battery Meter", systemImage: "battery.100percent") {
            Text("…")
        }
    }
}
