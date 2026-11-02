import Testing
import Foundation
@testable import BatteryCore

@Suite struct BatteryReadingTests {
    @Test func healthAndPower() {
        let r = BatteryReading(
            timestamp: Date(timeIntervalSince1970: 0),
            percent: 33, remainingCapacity: 1515, fullChargeCapacity: 4575,
            designCapacity: 4629, cycleCount: 100, designCycleCount: 1000,
            voltage: 11356, amperage: -362, isCharging: false,
            externalConnected: false, fullyCharged: false, adapterWatts: nil,
            notChargingReason: nil, osMinutesToEmpty: nil, osMinutesToFull: nil)
        #expect(abs(r.healthPercent - 98.83) < 0.01)
        #expect(abs(r.powerWatts - 4.111) < 0.001)
        #expect(abs(r.remainingWattHours - 17.204) < 0.001)
        #expect(abs(r.fullWattHours - 51.954) < 0.001)
    }

    @Test func healthNeverExceedsOneHundred() {
        // A new cell can measure slightly above its design capacity (4666 vs 4629 mAh).
        let r = BatteryReading(
            timestamp: Date(timeIntervalSince1970: 0),
            percent: 61, remainingCapacity: 2710, fullChargeCapacity: 4666,
            designCapacity: 4629, cycleCount: 9, designCycleCount: 1000,
            voltage: 11853, amperage: -662, isCharging: false,
            externalConnected: false, fullyCharged: false)
        #expect(r.healthPercent == 100)
    }

    private func reading(full: Int, nominal: Int?) -> BatteryReading {
        BatteryReading(
            timestamp: Date(timeIntervalSince1970: 0),
            percent: 50, remainingCapacity: 2000, fullChargeCapacity: full,
            designCapacity: 4629, cycleCount: 9, designCycleCount: 1000,
            voltage: 11853, amperage: -662, isCharging: false,
            externalConnected: false, fullyCharged: false, nominalChargeCapacity: nominal)
    }

    @Test func healthUsesNominalCapacityWhenPresent() {
        #expect(abs(reading(full: 4666, nominal: 4400).healthPercent - 95.06) < 0.01)
    }

    @Test func healthFallsBackToFullChargeWhenNominalMissing() {
        #expect(abs(reading(full: 4575, nominal: nil).healthPercent - 98.83) < 0.01)
    }

    @Test func zeroNominalCountsAsMissing() {
        #expect(abs(reading(full: 4575, nominal: 0).healthPercent - 98.83) < 0.01)
    }
}
