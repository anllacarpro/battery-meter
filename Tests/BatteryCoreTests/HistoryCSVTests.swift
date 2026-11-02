import Testing
import Foundation
@testable import BatteryCore

@Suite struct HistoryCSVTests {
    private static let header = "timestamp,percent,remaining_mah,full_charge_mah,design_mah,nominal_mah,cycles,voltage_mv,amperage_ma,charging,external_power"

    private func reading(nominal: Int?) -> BatteryReading {
        BatteryReading(
            timestamp: Date(timeIntervalSince1970: 0),
            percent: 61, remainingCapacity: 2710, fullChargeCapacity: 4666,
            designCapacity: 4629, cycleCount: 9,
            voltage: 11853, amperage: -662, isCharging: false,
            externalConnected: false, fullyCharged: false,
            nominalChargeCapacity: nominal)
    }

    @Test func emptyHistoryIsHeaderOnly() {
        #expect(HistoryCSV.encode([]) == Self.header + "\n")
    }

    @Test func rowFormatsEveryColumn() {
        let csv = HistoryCSV.encode([reading(nominal: 4785)])
        #expect(csv == Self.header + "\n1970-01-01T00:00:00Z,61,2710,4666,4629,4785,9,11853,-662,false,false\n")
    }

    @Test func missingNominalIsEmptyField() {
        let csv = HistoryCSV.encode([reading(nominal: nil)])
        #expect(csv.contains("4629,,9,"))
    }
}
