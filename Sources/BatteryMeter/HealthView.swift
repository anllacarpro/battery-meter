import SwiftUI
import BatteryCore

/// Raw hardware values in the registry's own units, so they can be checked against
/// `ioreg -rn AppleSmartBattery`. Optional keys hide their row.
struct HealthView: View {
    let reading: BatteryReading?

    var body: some View {
        if let reading {
            Form {
                Section {
                    row("Design capacity", "\(reading.designCapacity.formatted()) mAh")
                    row("Full charge capacity", "\(reading.fullChargeCapacity.formatted()) mAh")
                    if let nominal = reading.nominalChargeCapacity {
                        row("Nominal charge capacity", "\(nominal.formatted()) mAh")
                    }
                    row("Health", BatteryFormat.percent(reading.healthPercent))
                    row("Cycle count", BatteryFormat.cycles(reading))
                } header: {
                    // Section headers are inset to the row text; pull the title back to
                    // the card edge so it lines up with the other panes' titles.
                    PaneTitle("Health")
                        .foregroundStyle(.primary)
                        .padding(.leading, -10)
                        .padding(.bottom, 8)
                }
                Section("Electrical") {
                    row("Voltage", "\(reading.voltage.formatted()) mV")
                    row("Amperage", "\(BatteryFormat.signed(Double(reading.amperage), digits: 0)) mA")
                }
                if reading.adapterWatts != nil || reading.notChargingReason != nil {
                    Section("Charger") {
                        if let watts = reading.adapterWatts {
                            row("Adapter", "\(watts) W")
                        }
                        if let reason = reading.notChargingReason {
                            row("Not charging reason", reason == 0 ? "None" : "Code \(reason)")
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            EmptyStateView()
                .frame(maxHeight: .infinity)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }
}
