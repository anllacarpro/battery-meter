import Testing
import Foundation
@testable import BatteryCore

@Suite struct ChargingReportTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func reading(_ t: Date, percent: Int = 50, ac: Bool = false, cycles: Int = 0, watts: Int? = nil) -> BatteryReading {
        BatteryReading(
            timestamp: t, percent: percent, remainingCapacity: 0, fullChargeCapacity: 0,
            designCapacity: 0, cycleCount: cycles, voltage: 12_000, amperage: 0,
            isCharging: false, externalConnected: ac, fullyCharged: false, adapterWatts: watts)
    }

    @Test func plugInAndUnplugMedians() {
        var history: [BatteryReading] = []
        let plugIns = [20, 30, 40]
        let unplugs = [80, 90, 100]
        for i in 0..<3 {
            let base = now.addingTimeInterval(-Double(3 - i) * 3600)
            history.append(reading(base, percent: plugIns[i], ac: false))
            history.append(reading(base.addingTimeInterval(60), percent: plugIns[i] + 1, ac: true))
            history.append(reading(base.addingTimeInterval(120), percent: unplugs[i], ac: true))
            history.append(reading(base.addingTimeInterval(180), percent: unplugs[i] - 1, ac: false))
        }
        let report = ChargingReport.build(history: history, now: now)
        #expect(report.chargeCount == 3)
        #expect(report.typicalPlugInPercent == 30)
        #expect(report.typicalUnplugPercent == 90)
    }

    @Test func timeAtFull() {
        let history = (0...120).map { reading(now.addingTimeInterval(-7200 + Double($0) * 60), percent: 100, ac: true) }
        let report = ChargingReport.build(history: history, now: now)
        let value = report.averageDailyTimeAtFull
        #expect(value != nil)
        #expect(abs((value ?? 0) - 7200.0 / 7.0) <= 1)
    }

    @Test func cyclesPerWeekNeedsAWeek() {
        let short = [
            reading(now.addingTimeInterval(-3 * 86_400), cycles: 8),
            reading(now, cycles: 9),
        ]
        #expect(ChargingReport.build(history: short, now: now).cyclesPerWeek == nil)

        let long = [
            reading(now.addingTimeInterval(-14 * 86_400), cycles: 8),
            reading(now, cycles: 10),
        ]
        #expect(ChargingReport.build(history: long, now: now).cyclesPerWeek == 1.0)
    }

    @Test func usualCharger() {
        let history = [60, 60, 30].enumerated().map { i, w in
            reading(now.addingTimeInterval(Double(i) * 60), ac: true, watts: w)
        }
        #expect(ChargingReport.build(history: history, now: now).usualChargerWatts == 60)
    }

    @Test func emptyHistory() {
        let report = ChargingReport.build(history: [], now: now)
        #expect(report.chargeCount == 0)
        #expect(report.typicalPlugInPercent == nil)
        #expect(report.typicalUnplugPercent == nil)
        #expect(report.averageDailyTimeAtFull == nil)
        #expect(report.cyclesPerWeek == nil)
        #expect(report.usualChargerWatts == nil)
    }
}
