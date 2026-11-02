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
}
