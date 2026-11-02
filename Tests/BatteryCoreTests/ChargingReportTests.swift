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

    /// A battery reading, two AC readings and a battery reading, 60 s apart, starting at `start`.
    func run(at start: Date, plugIn: Int, unplug: Int) -> [BatteryReading] {
        [
            reading(start, percent: plugIn, ac: false),
            reading(start.addingTimeInterval(60), percent: plugIn + 1, ac: true),
            reading(start.addingTimeInterval(120), percent: unplug, ac: true),
            reading(start.addingTimeInterval(180), percent: unplug - 1, ac: false),
        ]
    }

    func runs(plugIns: [Int], unplugs: [Int]) -> [BatteryReading] {
        plugIns.indices.flatMap { i in
            run(at: now.addingTimeInterval(-Double(plugIns.count - i) * 3600), plugIn: plugIns[i], unplug: unplugs[i])
        }
    }

    @Test func gapOverThreeHundredSecondsSplitsRuns() {
        let t = now.addingTimeInterval(-3600)
        let split = [
            reading(t, percent: 50, ac: true),
            reading(t.addingTimeInterval(301), percent: 60, ac: true),
        ]
        #expect(ChargingReport.build(history: split, now: now).chargeCount == 2)

        let joined = [
            reading(t, percent: 50, ac: true),
            reading(t.addingTimeInterval(300), percent: 60, ac: true),
        ]
        #expect(ChargingReport.build(history: joined, now: now).chargeCount == 1)
    }

    @Test func plugInFallsBackToRunsFirstPercent() {
        let t = now.addingTimeInterval(-3600)
        // Previous reading is on AC but too far back to join the run.
        let afterAC = [
            reading(t, percent: 40, ac: true),
            reading(t.addingTimeInterval(400), percent: 45, ac: true),
        ]
        let r1 = ChargingReport.build(history: afterAC, now: now)
        #expect(r1.chargeCount == 2)
        #expect(r1.typicalPlugInPercent == 40) // median of [40, 45], lower middle

        // Previous reading is on battery but more than 300 s earlier.
        let farBattery = [
            reading(t, percent: 10, ac: false),
            reading(t.addingTimeInterval(400), percent: 55, ac: true),
        ]
        #expect(ChargingReport.build(history: farBattery, now: now).typicalPlugInPercent == 55)

        // No previous reading at all.
        let first = [reading(t, percent: 65, ac: true)]
        #expect(ChargingReport.build(history: first, now: now).typicalPlugInPercent == 65)

        // Previous battery reading within 300 s is used.
        let near = [
            reading(t, percent: 10, ac: false),
            reading(t.addingTimeInterval(300), percent: 55, ac: true),
        ]
        #expect(ChargingReport.build(history: near, now: now).typicalPlugInPercent == 10)
    }

    @Test func unplugLevelNeedsABatteryReadingSoonAfter() {
        let t = now.addingTimeInterval(-3600)
        let lateBattery = [
            reading(t, percent: 50, ac: true),
            reading(t.addingTimeInterval(60), percent: 90, ac: true),
            reading(t.addingTimeInterval(60 + 301), percent: 88, ac: false),
        ]
        let r1 = ChargingReport.build(history: lateBattery, now: now)
        #expect(r1.chargeCount == 1)
        #expect(r1.typicalUnplugPercent == nil)

        let endsOnAC = [
            reading(t, percent: 50, ac: true),
            reading(t.addingTimeInterval(60), percent: 90, ac: true),
        ]
        #expect(ChargingReport.build(history: endsOnAC, now: now).typicalUnplugPercent == nil)

        let onTime = [
            reading(t, percent: 50, ac: true),
            reading(t.addingTimeInterval(60), percent: 90, ac: true),
            reading(t.addingTimeInterval(360), percent: 88, ac: false),
        ]
        #expect(ChargingReport.build(history: onTime, now: now).typicalUnplugPercent == 90)
    }

    @Test func shuffledInputMatchesSortedInput() {
        var sorted = runs(plugIns: [20, 30, 40], unplugs: [80, 90, 100])
        sorted += (0...10).map { reading(now.addingTimeInterval(-600 + Double($0) * 60), percent: 100, ac: true, cycles: 5, watts: 60) }
        sorted.append(reading(now.addingTimeInterval(-10 * 86_400), cycles: 3))
        sorted.sort { $0.timestamp < $1.timestamp }
        let expected = ChargingReport.build(history: sorted, now: now)

        let reversed = Array(sorted.reversed())
        let interleaved = sorted.indices.filter { $0 % 2 == 0 } + sorted.indices.filter { $0 % 2 == 1 }
        #expect(ChargingReport.build(history: reversed, now: now) == expected)
        #expect(ChargingReport.build(history: interleaved.map { sorted[$0] }, now: now) == expected)
    }

    @Test func timeAtFullOnlyCountsRecentFullACPairs() {
        let recent = reading(now.addingTimeInterval(-60), percent: 50, ac: true)
        let old = [
            reading(now.addingTimeInterval(-8 * 86_400), percent: 100, ac: true),
            reading(now.addingTimeInterval(-8 * 86_400 + 60), percent: 100, ac: true),
            recent,
        ]
        #expect(ChargingReport.build(history: old, now: now).averageDailyTimeAtFull == 0)

        let t = now.addingTimeInterval(-3600)
        let notFull = [
            reading(t, percent: 99, ac: true),
            reading(t.addingTimeInterval(60), percent: 100, ac: true),
            reading(t.addingTimeInterval(120), percent: 100, ac: false),
            reading(t.addingTimeInterval(180), percent: 100, ac: true),
            reading(t.addingTimeInterval(240), percent: 99, ac: true),
        ]
        #expect(ChargingReport.build(history: notFull, now: now).averageDailyTimeAtFull == 0)

        // A pair more than 300 s apart is not continuous.
        let gap = [
            reading(t, percent: 100, ac: true),
            reading(t.addingTimeInterval(301), percent: 100, ac: true),
        ]
        #expect(ChargingReport.build(history: gap, now: now).averageDailyTimeAtFull == 0)
    }

    @Test func medianOfEvenCountIsLowerMiddle() {
        let history = runs(plugIns: [20, 30, 40, 50], unplugs: [60, 70, 80, 90])
        let report = ChargingReport.build(history: history, now: now)
        #expect(report.chargeCount == 4)
        #expect(report.typicalPlugInPercent == 30)
        #expect(report.typicalUnplugPercent == 70)
    }

    @Test func chargerTieGoesToHigherWattsAndIgnoresBattery() {
        var history = [60, 60, 30, 30].enumerated().map { i, w in
            reading(now.addingTimeInterval(Double(i) * 60), ac: true, watts: w)
        }
        history += (0..<5).map { reading(now.addingTimeInterval(1000 + Double($0) * 60), ac: false, watts: 90) }
        #expect(ChargingReport.build(history: history, now: now).usualChargerWatts == 60)
    }

    @Test func chargerIgnoresZeroOrNegativeWatts() {
        let mixed = [0, 0, 0, -5, 30].enumerated().map { i, w in
            reading(now.addingTimeInterval(Double(i) * 60), ac: true, watts: w)
        }
        #expect(ChargingReport.build(history: mixed, now: now).usualChargerWatts == 30)

        let zeros = [0, 0].enumerated().map { i, w in
            reading(now.addingTimeInterval(Double(i) * 60), ac: true, watts: w)
        }
        #expect(ChargingReport.build(history: zeros, now: now).usualChargerWatts == nil)
    }

    @Test func negativeCycleDeltaGivesNil() {
        let replaced = [
            reading(now.addingTimeInterval(-14 * 86_400), cycles: 500),
            reading(now, cycles: 3),
        ]
        #expect(ChargingReport.build(history: replaced, now: now).cyclesPerWeek == nil)

        let unchanged = [
            reading(now.addingTimeInterval(-14 * 86_400), cycles: 7),
            reading(now, cycles: 7),
        ]
        #expect(ChargingReport.build(history: unchanged, now: now).cyclesPerWeek == 0)
    }

    @Test func allBatteryHistoryHasNoChargingData() {
        let history = (0..<10).map { reading(now.addingTimeInterval(-Double($0) * 60), percent: 80 - $0, ac: false) }
        let report = ChargingReport.build(history: history, now: now)
        #expect(report.chargeCount == 0)
        #expect(report.typicalPlugInPercent == nil)
        #expect(report.typicalUnplugPercent == nil)
        #expect(report.averageDailyTimeAtFull == nil)
        #expect(report.cyclesPerWeek == nil)
        #expect(report.usualChargerWatts == nil)
    }

    @Test func allACHistoryFallsBackForPlugInAndHasNoUnplug() {
        let history = [50, 60, 70].enumerated().map { i, p in
            reading(now.addingTimeInterval(-300 + Double(i) * 60), percent: p, ac: true)
        }
        let report = ChargingReport.build(history: history, now: now)
        #expect(report.chargeCount == 1)
        #expect(report.typicalPlugInPercent == 50)
        #expect(report.typicalUnplugPercent == nil)
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
