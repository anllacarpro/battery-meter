import Testing
import Foundation
@testable import BatteryCore

@Suite struct UsageReportTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    /// 2026-11-02 12:00:00 UTC
    static let now = Date(timeIntervalSince1970: 1_793_620_800)

    static func reading(at date: Date, percent: Int, external: Bool = false) -> BatteryReading {
        BatteryReading(
            timestamp: date, percent: percent, remainingCapacity: 2500, fullChargeCapacity: 5000,
            designCapacity: 5000, cycleCount: 10, voltage: 10_000, amperage: -600,
            isCharging: false, externalConnected: external, fullyCharged: false)
    }

    /// 61 readings 60 s apart ending 100 s before `now`, dropping 1% every 6 readings.
    static func discharge(external: Bool = false) -> [BatteryReading] {
        let start = now.addingTimeInterval(-3700)
        return (0...60).map { i in
            reading(at: start.addingTimeInterval(Double(i) * 60), percent: 90 - i / 6, external: external)
        }
    }

    @Test func continuousDischargeToday() {
        let report = UsageReport.build(history: Self.discharge(), now: Self.now, calendar: Self.calendar)
        let today = report.days.last!
        #expect(today.batteryTime == 3600)
        #expect(today.percentUsed == 10)
        #expect(abs(today.averageWatts! - 6) < 0.01)
        for day in report.days.dropLast() {
            #expect(day.batteryTime == 0)
            #expect(day.percentUsed == 0)
            #expect(day.averageWatts == nil)
        }
        #expect(report.weeks.last!.batteryTime == 3600)
        #expect(report.hasData)
    }

    @Test func gapIsNotBatteryTime() {
        let history = [
            Self.reading(at: Self.now.addingTimeInterval(-7200), percent: 50),
            Self.reading(at: Self.now, percent: 40),
        ]
        let report = UsageReport.build(history: history, now: Self.now, calendar: Self.calendar)
        #expect(report.days.last!.batteryTime == 0)
        #expect(report.days.last!.percentUsed == 0)
        #expect(!report.hasData)
    }

    @Test func acReadingsIgnored() {
        let report = UsageReport.build(history: Self.discharge(external: true), now: Self.now, calendar: Self.calendar)
        #expect(!report.hasData)
        #expect(report.days.last!.batteryTime == 0)
    }

    @Test func unsortedInputSameResult() {
        let sorted = Self.discharge()
        let shuffled = sorted.enumerated().sorted { ($0.offset * 37) % 61 < ($1.offset * 37) % 61 }.map(\.element)
        #expect(shuffled != sorted)
        let a = UsageReport.build(history: sorted, now: Self.now, calendar: Self.calendar)
        let b = UsageReport.build(history: shuffled, now: Self.now, calendar: Self.calendar)
        #expect(a == b)
    }

    @Test func sevenDaysAndFourWeeks() {
        let report = UsageReport.build(history: [], now: Self.now, calendar: Self.calendar)
        #expect(report.days.count == 7)
        #expect(report.weeks.count == 4)
        #expect(report.days.last!.start == Self.calendar.startOfDay(for: Self.now))
        #expect(!report.hasData)
    }
}
