import Foundation
import Testing
@testable import BatteryCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func reading(
    at offset: TimeInterval, mV: Int = 12_000, mA: Int, remaining: Int = 4_000,
    charging: Bool = false, external: Bool = false, full: Bool = false, osToFull: Int? = nil
) -> BatteryReading {
    BatteryReading(
        timestamp: t0.addingTimeInterval(offset), percent: 50, remainingCapacity: remaining,
        fullChargeCapacity: 8_000, designCapacity: 8_500, cycleCount: 100,
        voltage: mV, amperage: mA, isCharging: charging, externalConnected: external,
        fullyCharged: full, osMinutesToFull: osToFull)
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
        for i in 0..<180 {
            let offset = TimeInterval(i * 10)
            let mA = i % 2 == 0 ? -250 : -750
            let state = est.update(with: reading(at: offset, mA: mA))
            // Settled window: the EMA seeds from the first sample (3 W), so the start-up
            // transient decays with a 300 s half-life; by 20 min only 6% of the seed remains.
            if offset >= 1_200, let t = timeLeft(state) { samples.append(t) }
        }
        let hi = samples.max()!, lo = samples.min()!
        #expect((hi - lo) / hi < 0.10)
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

    @Test func chargingUsesOSTimeToFull() {
        var est = PowerEstimator()
        let state = est.update(with: reading(at: 0, mA: 2_000, charging: true, external: true, osToFull: 65))
        #expect(state == .charging(timeToFull: 3900))
    }

    @Test func chargingWithoutOSEstimateIsNil() {
        var est = PowerEstimator()
        let state = est.update(with: reading(at: 0, mA: 2_000, charging: true, external: true))
        #expect(state == .charging(timeToFull: nil))
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
