import Testing
import Foundation
@testable import BatteryCore

@Suite struct DailyHealthTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func reading(day: Int, full: Int, nominal: Int?) -> BatteryReading {
        BatteryReading(
            timestamp: start.addingTimeInterval(Double(day) * 86_400),
            percent: 50, remainingCapacity: 2000, fullChargeCapacity: full,
            designCapacity: 4629, cycleCount: 9, designCycleCount: 1000,
            voltage: 11853, amperage: -662, isCharging: false,
            externalConnected: false, fullyCharged: false, nominalChargeCapacity: nominal)
    }

    @Test func mixedHistoryKeepsOnlyNominalBasedPoints() {
        let old = (0..<5).map { reading(day: $0, full: 3935, nominal: nil) }      // ~85%
        let new = (5..<10).map { reading(day: $0, full: 4000, nominal: 4073) }    // ~88%
        let points = DailyHealth.points(in: old + new)
        #expect(points.count == 5)
        #expect(points.allSatisfy { abs($0.percent - 87.99) < 0.05 })
    }

    @Test func historyWithoutNominalIsUnchanged() {
        let history = (0..<5).map { reading(day: $0, full: 3935, nominal: nil) }
        let points = DailyHealth.points(in: history)
        #expect(points.count == 5)
        #expect(points.allSatisfy { abs($0.percent - 85.0) < 0.05 })
    }
}
