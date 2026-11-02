import Testing
import Foundation
@testable import BatteryCore

@Suite struct FullChargeLearnerTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func reading(at offset: TimeInterval, percent: Int, external: Bool = false,
                        fullCapacity: Int = 5000, voltage: Int = 10_400) -> BatteryReading {
        BatteryReading(
            timestamp: t0.addingTimeInterval(offset), percent: percent,
            remainingCapacity: fullCapacity * percent / 100, fullChargeCapacity: fullCapacity,
            designCapacity: 5000, cycleCount: 10, voltage: voltage, amperage: -500,
            isCharging: false, externalConnected: external, fullyCharged: false)
    }

    /// Readings every 60 s from `startOffset`, percent falling linearly from `from` to `to` over `minutes`.
    static func run(startOffset: TimeInterval, minutes: Int, from: Int, to: Int) -> [BatteryReading] {
        (0...minutes).map { m in
            let p = Double(from) + (Double(to - from) * Double(m) / Double(minutes))
            return reading(at: startOffset + Double(m) * 60, percent: Int(p.rounded()))
        }
    }

    @Test func singleSession() {
        let history = Self.run(startOffset: 0, minutes: 120, from: 100, to: 80)
        let sessions = FullChargeLearner.sessions(in: history)
        #expect(sessions.count == 1)
        #expect(sessions[0].percentDrop == 20)
        #expect(abs(sessions[0].hoursPerFullCharge - 10) < 1e-9)
        #expect(sessions[0].start == Self.t0)
        #expect(sessions[0].end == Self.t0.addingTimeInterval(7200))
    }

    @Test func gapSplitsSession() {
        let a = Self.run(startOffset: 0, minutes: 30, from: 100, to: 85)
        let b = Self.run(startOffset: 50 * 60, minutes: 30, from: 85, to: 70)
        let sessions = FullChargeLearner.sessions(in: a + b)
        #expect(sessions.count == 2)
        for s in sessions {
            #expect(abs(s.end.timeIntervalSince(s.start) - 1800) < 1e-9)
            #expect(s.percentDrop == 15)
        }
        #expect(sessions[0].end <= sessions[1].start.addingTimeInterval(-1200))
    }

    @Test func shortSessionIgnored() {
        let history = Self.run(startOffset: 0, minutes: 60, from: 100, to: 95)
        #expect(FullChargeLearner.sessions(in: history).isEmpty)
    }

    @Test func briefLargeDropIgnored() {
        let history = Self.run(startOffset: 0, minutes: 10, from: 100, to: 80)
        #expect(FullChargeLearner.sessions(in: history).isEmpty)
    }

    @Test func externalPowerEndsSession() {
        let a = Self.run(startOffset: 0, minutes: 60, from: 100, to: 90)
        let plugged = Self.reading(at: 61 * 60, percent: 91, external: true)
        let b = Self.run(startOffset: 62 * 60, minutes: 60, from: 91, to: 80)
        #expect(FullChargeLearner.sessions(in: a + [plugged] + b).count == 2)
    }

    @Test func recentWeighted() throws {
        // old session: 72 min for a 10 pt drop -> 12 h; new: 96 min for 20 pts -> 8 h
        let oldSession = Self.run(startOffset: 0, minutes: 72, from: 100, to: 90)
        let newSession = Self.run(startOffset: 3 * 3600, minutes: 96, from: 100, to: 80)
        let history = oldSession + newSession
        let est = try #require(FullChargeLearner.estimate(history: history, current: nil, liveWatts: nil))
        #expect(!est.isEstimate)
        // weights: newest 1.0 (8 h), older 0.7 (12 h) -> (8 + 8.4) / 1.7
        #expect(abs(est.hours - (8 + 0.7 * 12) / 1.7) < 1e-9)
        #expect(est.hours < 10)
    }

    @Test func coldStartFallback() {
        let current = Self.reading(at: 0, percent: 50, fullCapacity: 5000, voltage: 10_400)
        #expect(abs(current.fullWattHours - 52) < 1e-9)
        let est = FullChargeLearner.estimate(history: [], current: current, liveWatts: 5.2)
        #expect(est == FullChargeEstimate(hours: 10, isEstimate: true))
    }

    @Test func noDataReturnsNil() {
        let current = Self.reading(at: 0, percent: 50)
        #expect(FullChargeLearner.estimate(history: [], current: nil, liveWatts: 5) == nil)
        #expect(FullChargeLearner.estimate(history: [], current: current, liveWatts: nil) == nil)
        #expect(FullChargeLearner.estimate(history: [], current: current, liveWatts: 0) == nil)
    }
}
