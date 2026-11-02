import Foundation

/// Encodes battery readings as CSV for export.
public enum HistoryCSV {
    static let header = "timestamp,percent,remaining_mah,full_charge_mah,design_mah,nominal_mah,cycles,voltage_mv,amperage_ma,charging,external_power"

    public static func encode(_ readings: [BatteryReading]) -> String {
        let formatter = ISO8601DateFormatter()
        var out = header + "\n"
        for r in readings {
            let fields: [String] = [
                formatter.string(from: r.timestamp),
                String(r.percent),
                String(r.remainingCapacity),
                String(r.fullChargeCapacity),
                String(r.designCapacity),
                r.nominalChargeCapacity.map(String.init) ?? "",
                String(r.cycleCount),
                String(r.voltage),
                String(r.amperage),
                String(r.isCharging),
                String(r.externalConnected),
            ]
            out += fields.joined(separator: ",") + "\n"
        }
        return out
    }
}
