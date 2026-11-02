import Foundation
import Testing
@testable import BatteryCore

private func ownerSample() -> [String: Any] {
    [
        "CurrentCapacity": 34,
        "CycleCount": 8,
        "DesignCycleCount9C": 1000,
        "Voltage": 11_356,
        "Amperage": NSNumber(value: UInt64(18446744073709551254)),
        "IsCharging": false,
        "ExternalConnected": false,
        "FullyCharged": false,
        "AvgTimeToEmpty": 214,
        "AvgTimeToFull": 65535,
        "BatteryData": [
            "DesignCapacity": 4629,
            "FullChargeCapacity": 4575,
            "RemainingCapacity": 1515,
        ] as [String: Any],
        "ChargerData": ["NotChargingReason": 128] as [String: Any],
        "AdapterDetails": ["FamilyCode": 0] as [String: Any],
    ]
}

@Suite struct BatteryParserTests {
    let date = Date(timeIntervalSince1970: 1_000)

    @Test func parsesOwnerSample() throws {
        let r = try #require(BatteryParser.parse(ownerSample(), at: date))
        #expect(r.timestamp == date)
        #expect(r.percent == 34)
        #expect(r.amperage == -362)
        #expect(r.cycleCount == 8)
        #expect(r.designCycleCount == 1000)
        #expect(r.designCapacity == 4629)
        #expect(r.fullChargeCapacity == 4575)
        #expect(r.remainingCapacity == 1515)
        #expect(r.voltage == 11_356)
        #expect(r.osMinutesToEmpty == 214)
        #expect(r.osMinutesToFull == nil)
        #expect(r.isCharging == false)
        #expect(r.notChargingReason == 128)
        #expect(r.adapterWatts == nil)
    }

    @Test func timestampTruncatedToWholeSeconds() throws {
        let r = try #require(BatteryParser.parse(ownerSample(), at: Date(timeIntervalSince1970: 1_000.873)))
        #expect(r.timestamp == date)
    }

    @Test func parsedReadingRoundTripsThroughStoreExactly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatteryParserTests-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(fileURL: url)
        let r = try #require(BatteryParser.parse(ownerSample(), at: Date(timeIntervalSince1970: 1_700_000_123.456)))
        try store.append(r)
        #expect(store.load(since: .distantPast) == [r])
    }

    @Test func missingAdapterWattsIsNil() throws {
        let r = try #require(BatteryParser.parse(ownerSample(), at: date))
        #expect(r.adapterWatts == nil)
    }

    @Test func absentAdapterAndChargerAreNil() throws {
        var raw = ownerSample()
        raw["AdapterDetails"] = nil
        raw["ChargerData"] = nil
        let r = try #require(BatteryParser.parse(raw, at: date))
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
        for key in ["CurrentCapacity", "Voltage", "Amperage", "CycleCount", "IsCharging", "ExternalConnected", "FullyCharged"] {
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
