import Foundation
import Testing
@testable import BatteryCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func reading(
    at offset: TimeInterval, mV: Int = 12_000, mA: Int, remaining: Int = 4_000,
    fullCapacity: Int = 8_000, percent: Int = 50,
    charging: Bool = false, external: Bool = false, full: Bool = false, osToFull: Int? = nil
) -> BatteryReading {
    BatteryReading(
        timestamp: t0.addingTimeInterval(offset), percent: percent, remainingCapacity: remaining,
        fullChargeCapacity: fullCapacity, designCapacity: 8_500, cycleCount: 100,
        voltage: mV, amperage: mA, isCharging: charging, externalConnected: external,
        fullyCharged: full, osMinutesToFull: osToFull)
}

private func timeToFull(_ state: PowerState) -> TimeInterval? {
    if case .charging(let t) = state { return t }
    return nil
}

private func timeLeft(_ state: PowerState) -> TimeInterval? {
    if case .onBattery(let t) = state { return t }
    return nil
}

@Suite struct PowerStateTests {
    @Test func steadyUnderNoisyDraw() {
        var est = PowerEstimator()
        var samples: [TimeInterval] = []
        // Voltage and capacity held constant; only amperage alternates (3 W / 9 W).
        // The headline smoother has an 1800 s half-life and seeds from the first sample (3 W),
        // so run 5 h (10 half-lives) and judge only the last hour, once the seed has decayed.
        for i in 0..<1_800 {
            let offset = TimeInterval(i * 10)
            let mA = i % 2 == 0 ? -250 : -750
            let state = est.update(with: reading(at: offset, mA: mA))
            if offset >= 4 * 3_600, let t = timeLeft(state) { samples.append(t) }
        }
        #expect(samples.count > 300)
        let hi = samples.max()!, lo = samples.min()!
        #expect((hi - lo) / hi < 0.02)
        // Settled on the 6 W average, not on either extreme.
        let expected = (4_000.0 * 12_000 / 1_000_000) / 6.0 * 3600
        #expect(abs(samples.last! - expected) / expected < 0.02)
    }

    @Test func headlineRecoversAfterLaunchSpike() throws {
        var est = PowerEstimator()
        // Drain-free fixture: constant remaining capacity and voltage, ~43 Wh left.
        // First reading 26.6 W (2 217 mA at 12 V), then a steady 8 W (667 mA).
        var state = est.update(with: reading(at: 0, mA: -2_217, remaining: 3_600), typicalWatts: 10.3)
        for i in 1...60 {
            state = est.update(with: reading(at: TimeInterval(i * 10), mA: -667, remaining: 3_600),
                               typicalWatts: 10.3)
        }
        let hours = try #require(timeLeft(state)) / 3600
        #expect(hours > 4.2 && hours < 5.2)
    }

    @Test func gapResetsSmoother() {
        var est = PowerEstimator()
        for i in 0..<60 { _ = est.update(with: reading(at: TimeInterval(i * 10), mA: -833)) } // ~10 W
        let state = est.update(with: reading(at: 590 + 400, mA: -167)) // ~2 W
        let remainingWh = 4_000.0 * 12_000 / 1_000_000
        let expected = remainingWh / (167.0 * 12_000 / 1_000_000) * 3600
        let t = try! #require(timeLeft(state))
        #expect(abs(t - expected) / expected < 0.01)
    }

    @Test func unplugResetsSmoother() {
        var est = PowerEstimator()
        for i in 0..<6 {
            _ = est.update(with: reading(at: TimeInterval(i * 10), mA: 2_500, charging: true, external: true))
        }
        let state = est.update(with: reading(at: 60, mA: -333))
        let w = 333.0 * 12_000 / 1_000_000
        let expected = (4_000.0 * 12_000 / 1_000_000) / w * 3600
        let t = try! #require(timeLeft(state))
        #expect(abs(t - expected) / expected < 0.001)
        #expect(abs(est.liveWatts! - w) < 1e-9)
    }

    @Test func nearZeroDrawIsUnknown() {
        var est = PowerEstimator()
        let state = est.update(with: reading(at: 0, mA: -25)) // 0.3 W
        #expect(state == .onBattery(timeLeft: nil))
    }

    @Test func timeLeftCappedAt99Hours() {
        var est = PowerEstimator()
        let state = est.update(with: reading(at: 0, mA: -50, remaining: 8_000)) // 0.6 W, 96 Wh -> 160 h
        #expect(state == .onBattery(timeLeft: 99 * 3600))
    }

    @Test func fullOnACIsPluggedIn() {
        var est = PowerEstimator()
        let state = est.update(with: reading(at: 0, mA: 0, charging: false, external: true, full: true))
        #expect(state == .pluggedIn)
    }

    @Test func chargingPrefersCurrentOverOSBelow80() {
        var est = PowerEstimator()
        // 4,000 mAh missing at 2,000 mA is 2 h; macOS's 65 min is ignored below 80%.
        let state = est.update(with: reading(at: 0, mA: 2_000, charging: true, external: true, osToFull: 65))
        #expect(state == .charging(timeToFull: 7200))
    }

    @Test func chargingWithoutOSEstimateUsesCurrent() {
        var est = PowerEstimator()
        let state = est.update(with: reading(at: 0, mA: 2_000, charging: true, external: true))
        #expect(state == .charging(timeToFull: 7200))
    }

    @Test func chargingUsesSmoothedCurrent() throws {
        var est = PowerEstimator()
        var state = PowerState.pluggedIn
        for i in 0..<30 {
            state = est.update(with: reading(
                at: TimeInterval(i * 10), mA: 2_000, remaining: 1_515, fullCapacity: 4_575,
                percent: 33, charging: true, external: true))
        }
        let t = try #require(timeToFull(state))
        #expect(abs(t - 1.53 * 3600) < 1)  // 3,060 mAh / 2,000 mA
    }

    @Test func chargingIgnoresOSSpikeEarly() throws {
        var est = PowerEstimator()
        // Owner's data: macOS said 579 min at 28% while the current ramped up on a 60 W adapter.
        let state = est.update(with: reading(
            at: 0, mA: 2_000, remaining: 1_281, fullCapacity: 4_575, percent: 28,
            charging: true, external: true, osToFull: 579))
        let t = try #require(timeToFull(state))
        let expected = (4_575.0 - 1_281) / 2_000 * 3600
        #expect(abs(t - expected) < 1)
        #expect(t < 579 * 60 / 2)
    }

    @Test func nearFullUsesLargerOfOSAndCurrent() {
        // 675 mAh missing at 1,500 mA is 27 min.
        func state(os: Int) -> PowerState {
            var est = PowerEstimator()
            return est.update(with: reading(
                at: 0, mA: 1_500, remaining: 3_900, fullCapacity: 4_575, percent: 85,
                charging: true, external: true, osToFull: os))
        }
        #expect(state(os: 60) == .charging(timeToFull: 3600))  // tapering: macOS is longer
        #expect(state(os: 10) == .charging(timeToFull: 1620))  // current is longer
    }

    @Test func lowChargeCurrentIsUnknown() {
        var est = PowerEstimator()
        let state = est.update(with: reading(
            at: 0, mA: 80, percent: 95, charging: true, external: true, osToFull: 20))
        #expect(state == .charging(timeToFull: nil))
    }

    @Test func chargeGapResetsSmoother() throws {
        var est = PowerEstimator()
        for i in 0..<60 {
            _ = est.update(with: reading(at: TimeInterval(i * 10), mA: 3_000, charging: true, external: true))
        }
        let state = est.update(with: reading(at: 590 + 400, mA: 1_000, charging: true, external: true))
        let t = try #require(timeToFull(state))
        #expect(abs(t - 4_000.0 / 1_000 * 3600) < 1)
    }

    @Test func liveTilesUseSignedAmpsAndUnits() {
        var est = PowerEstimator()
        #expect(est.liveWatts == nil && est.liveVolts == nil && est.liveAmps == nil)
        _ = est.update(with: reading(at: 0, mV: 12_500, mA: -800))
        #expect(abs(est.liveVolts! - 12.5) < 1e-9)
        #expect(abs(est.liveAmps! - (-0.8)) < 1e-9)
        #expect(abs(est.liveWatts! - 10.0) < 1e-9)
    }

    @Test func formatting() {
        #expect(DurationText.short(24_000) == "6h 40m")
        #expect(DurationText.short(2_690) == "45m")
        #expect(DurationText.short(100) == "0m")
        #expect(DurationText.short(362_000) == "99h 0m")
    }
}
