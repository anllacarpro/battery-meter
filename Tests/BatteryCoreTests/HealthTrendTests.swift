import Testing
import Foundation
@testable import BatteryCore

@Suite struct HealthTrendTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func points(_ count: Int, _ percent: (Int) -> Double) -> [HealthPoint] {
        (0..<count).map { HealthPoint(day: start.addingTimeInterval(Double($0) * 86_400), percent: percent($0)) }
    }

    @Test func tooFewDays() {
        let result = HealthTrend.build(points: points(10) { _ in 98 })
        #expect(result == .notEnoughData(daysCollected: 10))
    }

    @Test func enoughPointsButTooShortASpan() {
        // 14 points within a single day: plenty of points, not enough time.
        let pts = (0..<14).map { HealthPoint(day: start.addingTimeInterval(Double($0) * 60), percent: 98) }
        #expect(HealthTrend.build(points: pts) == .notEnoughData(daysCollected: 14))
    }

    @Test func flatIsSteady() {
        guard case .steady(let current) = HealthTrend.build(points: points(30) { _ in 98.8 }) else {
            Issue.record("expected steady"); return
        }
        #expect(abs(current - 98.8) < 1e-9)
    }

    @Test func tinySlopeIsSteady() {
        let result = HealthTrend.build(points: points(30) { 99 - 0.0005 * Double($0) })
        guard case .steady = result else { Issue.record("expected steady, got \(result)"); return }
    }

    @Test func decliningProjects80() {
        let pts = points(30) { 100 - 3 * Double($0) / 29 }
        guard case .declining(let current, let loss, let reaches80) = HealthTrend.build(points: pts) else {
            Issue.record("expected declining"); return
        }
        #expect(abs(current - 97) < 0.01)
        #expect(abs(loss - 3.10) <= 0.05)
        let days = (reaches80?.timeIntervalSince(pts.last!.day) ?? 0) / 86_400
        #expect(abs(days - 164) <= 2)
    }

    @Test func alreadyBelow80HasNoDate() {
        let pts = points(30) { 79 - Double($0) * 0.1 }
        guard case .declining(_, _, let reaches80) = HealthTrend.build(points: pts) else {
            Issue.record("expected declining"); return
        }
        #expect(reaches80 == nil)
    }

    @Test func farFutureHasNoDate() {
        // 0.002 %/day from ~99 is ~9,500 days out, past the 10-year cap.
        let pts = points(30) { 99 - 0.002 * Double($0) }
        guard case .declining(_, _, let reaches80) = HealthTrend.build(points: pts) else {
            Issue.record("expected declining"); return
        }
        #expect(reaches80 == nil)
    }

    @Test func dailyHealthMovedUnchanged() {
        func reading(_ t: Date, full: Int) -> BatteryReading {
            BatteryReading(
                timestamp: t, percent: 50, remainingCapacity: 0, fullChargeCapacity: full,
                designCapacity: 100, cycleCount: 0, voltage: 12_000, amperage: 0,
                isCharging: false, externalConnected: false, fullyCharged: false)
        }
        let offset = TimeInterval(TimeZone.current.secondsFromGMT())
        let day0 = (start.timeIntervalSince1970 + offset) / 86_400
        let localMidnight = day0.rounded(.down) * 86_400 - offset
        let d0 = Date(timeIntervalSince1970: localMidnight + 3600)
        let history = [
            reading(d0, full: 90), reading(d0.addingTimeInterval(60), full: 100),
            reading(d0.addingTimeInterval(86_400), full: 80),
        ]
        let result = DailyHealth.points(in: history)
        #expect(result.count == 2)
        #expect(result[0].day == Date(timeIntervalSince1970: localMidnight + 43_200))
        #expect(result[0].percent == 95)
        #expect(result[1].day == Date(timeIntervalSince1970: localMidnight + 86_400 + 43_200))
        #expect(result[1].percent == 80)
    }
}
