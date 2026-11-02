import Foundation
import Testing
@testable import BatteryCore

private func ownerSample() -> [String: Any] {
    [
        "CurrentCapacity": 63,
        "CycleCount": 8,
        "DesignCycleCount9C": 1000,
        "Voltage": 11_890,
        "Amperage": NSNumber(value: UInt64(18446744073709551254)),
        "IsCharging": false,
        "ExternalConnected": false,
        "FullyCharged": false,
        "AvgTimeToEmpty": 214,
        "AvgTimeToFull": 65535,
        "BatteryData": [
            "DesignCapacity": 4629,
            "FullChargeCapacity": 4500,
            "RemainingCapacity": 2835,
        ] as [String: Any],
    ]
}

@Suite struct BatteryParserTests {
    let date = Date(timeIntervalSince1970: 1_000)

    @Test func parsesOwnerSample() throws {
        let r = try #require(BatteryParser.parse(ownerSample(), at: date))
        #expect(r.timestamp == date)
        #expect(r.percent == 63)
        #expect(r.amperage == -362)
        #expect(r.cycleCount == 8)
        #expect(r.designCycleCount == 1000)
        #expect(r.designCapacity == 4629)
        #expect(r.fullChargeCapacity == 4500)
        #expect(r.remainingCapacity == 2835)
        #expect(r.voltage == 11_890)
        #expect(r.osMinutesToEmpty == 214)
        #expect(r.osMinutesToFull == nil)
        #expect(r.isCharging == false)
    }

    @Test func missingAdapterWattsIsNil() throws {
        let r = try #require(BatteryParser.parse(ownerSample(), at: date))
        #expect(r.adapterWatts == nil)
        #expect(r.notChargingReason == nil)
    }

    @Test func parsesAdapterAndChargerData() throws {
        var raw = ownerSample()
        raw["AdapterDetails"] = ["Watts": 96] as [String: Any]
        raw["ChargerData"] = ["NotChargingReason": 4] as [String: Any]
        let r = try #require(BatteryParser.parse(raw, at: date))
        #expect(r.adapterWatts == 96)
        #expect(r.notChargingReason == 4)
    }

    @Test func missingBatteryDataReturnsNil() {
        var raw = ownerSample()
        raw["BatteryData"] = nil
        #expect(BatteryParser.parse(raw, at: date) == nil)
    }

    @Test func missingTopLevelKeyReturnsNil() {
        for key in ["CurrentCapacity", "Voltage", "Amperage"] {
            var raw = ownerSample()
            raw[key] = nil
            #expect(BatteryParser.parse(raw, at: date) == nil, "\(key)")
        }
    }

    @Test func zeroDesignCapacityReturnsNil() {
        var raw = ownerSample()
        raw["BatteryData"] = ["DesignCapacity": 0, "FullChargeCapacity": 1, "RemainingCapacity": 1] as [String: Any]
        #expect(BatteryParser.parse(raw, at: date) == nil)
    }

    @Test func liveBatteryParses() throws {
        guard let raw = IOKitBatterySource().readRaw() else { return }
        let r = try #require(BatteryParser.parse(raw, at: date))
        #expect(r.designCapacity > 0)
    }
}
