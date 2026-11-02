import Foundation
import Testing
@testable import BatteryCore

private let now = Date(timeIntervalSince1970: 2_000_000_000)

private func reading(
    at date: Date, watts: Double, remainingWh: Double = 40, external: Bool = false
) -> BatteryReading {
    // 10 V, so mA = watts * 100 and mAh = Wh * 100.
    BatteryReading(
        timestamp: date, percent: 50, remainingCapacity: Int(remainingWh * 100),
        fullChargeCapacity: 8_000, designCapacity: 8_500, cycleCount: 100,
        voltage: 10_000, amperage: -Int((watts * 100).rounded()), isCharging: false,
        externalConnected: external, fullyCharged: false)
}

private func headline(_ est: PowerEstimator) -> TimeInterval? { est.runtime?.headline }

@Suite struct TypicalDrawTests {
    @Test func typicalIsMedianOfBatteryReadings() throws {
        var history: [BatteryReading] = (0..<30).map {
            reading(at: now.addingTimeInterval(-TimeInterval($0 * 60)), watts: 5)
        }
        history.append(reading(at: now.addingTimeInterval(-3_600), watts: 40))
        // Ignored: on AC, and older than 7 days.
        history += (0..<20).map {
            reading(at: now.addingTimeInterval(-TimeInterval($0 * 60)), watts: 60, external: true)
        }
        history += (0..<20).map {
            reading(at: now.addingTimeInterval(-8 * 86_400 - TimeInterval($0 * 60)), watts: 60)
        }
        let typical = try #require(TypicalDraw.watts(in: history, now: now))
        #expect(abs(typical - 5) < 0.01)
    }

    @Test func typicalNeedsThirtyReadings() {
        func history(_ n: Int) -> [BatteryReading] {
            (0..<n).map { reading(at: now.addingTimeInterval(-TimeInterval($0 * 60)), watts: 5) }
        }
        #expect(TypicalDraw.watts(in: history(29), now: now) == nil)
        #expect(TypicalDraw.watts(in: history(30), now: now) != nil)
    }

    @Test func headlineBlendsTypicalAndRecent() throws {
        var est = PowerEstimator()
        _ = est.update(with: reading(at: now, watts: 14, remainingWh: 40), typicalWatts: 6)
        let h = try #require(headline(est))
        #expect(abs(h - 4 * 3600) / (4 * 3600) < 0.01)
    }

    @Test func spikeAtLaunchDoesNotDominateHeadline() throws {
        var est = PowerEstimator()
        let state = est.update(with: reading(at: now, watts: 26.6, remainingWh: 43), typicalWatts: 6.7)
        let rt = try #require(est.runtime)
        #expect(try #require(rt.headline) > 2.5 * 3600)
        #expect(try #require(rt.atPace) < 1.7 * 3600)
        #expect(state == .onBattery(timeLeft: rt.headline))
    }

    @Test func noTypicalUsesRecentAndIsEstimate() throws {
        var est = PowerEstimator()
        _ = est.update(with: reading(at: now, watts: 10, remainingWh: 40))
        let rt = try #require(est.runtime)
        #expect(rt.isEstimate)
        #expect(rt.typicalWatts == nil)
        #expect(abs(try #require(rt.headline) - 4 * 3600) < 1)
        #expect(!rt.isHighUse)
    }

    @Test func highUseThresholds() throws {
        func rt(pace: Double, typical: Double) throws -> RuntimeEstimate {
            var est = PowerEstimator()
            _ = est.update(with: reading(at: now, watts: pace), typicalWatts: typical)
            return try #require(est.runtime)
        }
        #expect(try rt(pace: 26.6, typical: 6.7).isHighUse)
        #expect(try !rt(pace: 12, typical: 8).isHighUse)
        #expect(try !rt(pace: 9, typical: 2).isHighUse)
    }

    @Test func runtimeIsNilOffBattery() {
        var est = PowerEstimator()
        #expect(est.runtime == nil)
        _ = est.update(with: reading(at: now, watts: 10), typicalWatts: 6)
        #expect(est.runtime != nil)
        _ = est.update(with: reading(at: now.addingTimeInterval(10), watts: 10, external: true))
        #expect(est.runtime == nil)
        #expect(est.recentWatts != nil)  // re-seeded from the AC reading, not carried over
    }

    @Test func recentWattsResetsOnPowerSourceChange() {
        var est = PowerEstimator()
        _ = est.update(with: reading(at: now, watts: 30))
        _ = est.update(with: reading(at: now.addingTimeInterval(10), watts: 5, external: true))
        #expect(abs(est.recentWatts! - 5) < 1e-9)
    }

    @Test func evenCountMedianAveragesMiddlePair() throws {
        let history = (0..<32).map {
            reading(at: now.addingTimeInterval(-TimeInterval($0 * 60)), watts: 5 + Double($0 % 4))
        }  // eight each of 5, 6, 7, 8 W
        let typical = try #require(TypicalDraw.watts(in: history, now: now))
        #expect(abs(typical - 6.5) < 0.01)
    }

    @Test func futureReadingsAreExcluded() throws {
        var history = (0..<30).map {
            reading(at: now.addingTimeInterval(-TimeInterval($0 * 60)), watts: 5)
        }
        history += (0..<40).map { reading(at: now.addingTimeInterval(60 + TimeInterval($0)), watts: 90) }
        let typical = try #require(TypicalDraw.watts(in: history, now: now))
        #expect(abs(typical - 5) < 0.01)
    }

    @Test func sevenDayWindowBoundary() throws {
        let base = (0..<30).map {
            reading(at: now.addingTimeInterval(-TimeInterval($0 * 60)), watts: 5)
        }
        func extras(ageHours: Double) -> [BatteryReading] {
            (0..<40).map {
                reading(at: now.addingTimeInterval(-ageHours * 3_600 - TimeInterval($0)), watts: 50)
            }
        }
        let inside = try #require(TypicalDraw.watts(in: base + extras(ageHours: 6 * 24 + 23), now: now))
        #expect(abs(inside - 50) < 0.01)
        let outside = try #require(TypicalDraw.watts(in: base + extras(ageHours: 7 * 24 + 1), now: now))
        #expect(abs(outside - 5) < 0.01)
    }

    @Test func highUseBoundaries() throws {
        func isHighUse(pace: Double, typical: Double) throws -> Bool {
            var est = PowerEstimator()
            _ = est.update(with: reading(at: now, watts: pace), typicalWatts: typical)
            return try #require(est.runtime).isHighUse
        }
        #expect(try isHighUse(pace: 10, typical: 5))        // exactly 10 W and exactly 2x
        #expect(try !isHighUse(pace: 9.99, typical: 4))     // just under 10 W
        #expect(try !isHighUse(pace: 10, typical: 5.01))    // just under 2x
    }

    @Test func recentWattsResetsAfterGap() {
        var est = PowerEstimator()
        for i in 0...60 { _ = est.update(with: reading(at: now.addingTimeInterval(TimeInterval(i * 10)), watts: 20)) }
        #expect(abs(est.recentWatts! - 20) < 1e-9)
        _ = est.update(with: reading(at: now.addingTimeInterval(600 + 400), watts: 2))
        #expect(abs(est.recentWatts! - 2) < 1e-9)
    }
}
