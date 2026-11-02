import Testing
import Foundation
@testable import BatteryCore

@Suite struct ServiceAdviceTests {
    private func reading(fullCapacity: Int = 1000, cycles: Int = 9, designCycles: Int? = 1000) -> BatteryReading {
        BatteryReading(
            timestamp: Date(timeIntervalSince1970: 0),
            percent: 50, remainingCapacity: 500, fullChargeCapacity: fullCapacity,
            designCapacity: 1000, cycleCount: cycles, designCycleCount: designCycles,
            voltage: 11853, amperage: -662, isCharging: false,
            externalConnected: false, fullyCharged: false)
    }

    @Test func healthyBatteryNeedsNothing() {
        let advice = ServiceAdvice.advice(for: reading())
        #expect(advice == .none)
        #expect(advice.message == nil)
    }

    @Test func healthBelow80IsLowHealth() {
        #expect(ServiceAdvice.advice(for: reading(fullCapacity: 799)) == .lowHealth)
        #expect(ServiceAdvice.advice(for: reading(fullCapacity: 800)) == .none)
    }

    @Test func cyclesAtEightyPercentOfLimitIsHighCycles() {
        #expect(ServiceAdvice.advice(for: reading(cycles: 800)) == .highCycles)
        #expect(ServiceAdvice.advice(for: reading(cycles: 799)) == .none)
    }

    @Test func missingDesignCycleCountNeverTriggersCycles() {
        #expect(ServiceAdvice.advice(for: reading(cycles: 5000, designCycles: nil)) == .none)
    }

    @Test func lowHealthWinsOverHighCycles() {
        #expect(ServiceAdvice.advice(for: reading(fullCapacity: 700, cycles: 900)) == .lowHealth)
    }

    @Test func messages() {
        #expect(ServiceAdvice.lowHealth.message
            == "Health is below 80%, Apple's service threshold. Consider a battery service.")
        #expect(ServiceAdvice.highCycles.message
            == "This battery is near its rated cycle count. Health may start to drop faster.")
    }
}
