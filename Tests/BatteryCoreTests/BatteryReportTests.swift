import Testing
import Foundation
@testable import BatteryCore

@Suite struct BatteryReportTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    /// 2026-11-02 12:00:00 UTC
    static let now = Date(timeIntervalSince1970: 1_793_620_800)

    static func reading(at date: Date, percent: Int, external: Bool = false, full: Int = 5000) -> BatteryReading {
        BatteryReading(
            timestamp: date, percent: percent, remainingCapacity: 2500, fullChargeCapacity: full,
            designCapacity: 5000, cycleCount: 10, voltage: 10_000, amperage: external ? 500 : -600,
            isCharging: external, externalConnected: external, fullyCharged: false)
    }

    /// Two discharge runs (yesterday and today), a charging stretch between them.
    static func history() -> [BatteryReading] {
        func run(endingHoursAgo h: Double, from percent: Int, full: Int) -> [BatteryReading] {
            let start = now.addingTimeInterval(-h * 3600 - 3600)
            return (0...60).map { i in
                reading(at: start.addingTimeInterval(Double(i) * 60), percent: percent - i / 5, full: full)
            }
        }
        let charging = (0...30).map { i in
            reading(at: now.addingTimeInterval(-20 * 3600 + Double(i) * 60), percent: 70 + i / 2, external: true)
        }
        return run(endingHoursAgo: 26, from: 90, full: 4900) + charging + run(endingHoursAgo: 1, from: 95, full: 4800)
    }

    static let events = [
        PowerEvent(date: now.addingTimeInterval(-10 * 3600), kind: .sleep, onBattery: true, charge: 80, reason: nil),
        PowerEvent(date: now.addingTimeInterval(-8 * 3600), kind: .wake, onBattery: true, charge: 78, reason: .lid),
    ]

    static let appEnergy: [String: [String: Double]] = [
        "2026-11-02": ["Safari": 600, "Mail": 300],
        "2026-11-01": ["Safari": 300],
    ]

    @Test func composesSubReports() {
        let history = Self.history()
        let report = BatteryReport.build(
            history: history, powerEvents: Self.events, appEnergy: Self.appEnergy,
            now: Self.now, calendar: Self.calendar)

        #expect(report.generated == Self.now)
        #expect(report.usage == UsageReport.build(history: history, now: Self.now, calendar: Self.calendar))
        #expect(report.charging == ChargingReport.build(history: history, now: Self.now))
        #expect(report.health == HealthTrend.build(points: DailyHealth.points(in: history)))
        #expect(report.sleep == SleepReport.build(events: Self.events, now: Self.now))
        #expect(report.apps == AppEnergyReport.build(days: Self.appEnergy, now: Self.now, calendar: Self.calendar))
        #expect(!report.apps.isEmpty)

        let oldestFirst = FullChargeLearner.sessions(in: history)
        #expect(oldestFirst.count == 2)
        #expect(report.sessions == Array(oldestFirst.reversed()))
        #expect(report.sessions[0].start > report.sessions[1].start)
    }
}
