import Foundation
import Testing
@testable import BatteryCore

@Suite struct MenuBarAppearanceTests {
    private let onBattery = PowerState.onBattery(timeLeft: nil)

    @Test func symbolMapping() {
        #expect(MenuBarAppearance.symbolName(percent: 100, state: onBattery) == "battery.100percent")
        #expect(MenuBarAppearance.symbolName(percent: 88, state: onBattery) == "battery.100percent")
        #expect(MenuBarAppearance.symbolName(percent: 75, state: onBattery) == "battery.75percent")
        #expect(MenuBarAppearance.symbolName(percent: 63, state: onBattery) == "battery.75percent")
        #expect(MenuBarAppearance.symbolName(percent: 50, state: onBattery) == "battery.50percent")
        #expect(MenuBarAppearance.symbolName(percent: 38, state: onBattery) == "battery.50percent")
        #expect(MenuBarAppearance.symbolName(percent: 25, state: onBattery) == "battery.25percent")
        #expect(MenuBarAppearance.symbolName(percent: 13, state: onBattery) == "battery.25percent")
        #expect(MenuBarAppearance.symbolName(percent: 5, state: onBattery) == "battery.0percent")
        #expect(MenuBarAppearance.symbolName(percent: 50, state: .charging(timeToFull: nil)) == "battery.100percent.bolt")
        #expect(MenuBarAppearance.symbolName(percent: 100, state: .pluggedIn) == "powerplug")
    }

    @Test func lowOnlyOnBattery() {
        #expect(MenuBarAppearance.isLow(percent: 10, state: onBattery))
        #expect(!MenuBarAppearance.isLow(percent: 10, state: .charging(timeToFull: nil)))
        #expect(!MenuBarAppearance.isLow(percent: 10, state: .pluggedIn))
        #expect(!MenuBarAppearance.isLow(percent: 11, state: onBattery))
    }

    @Test func accessibilityLabels() {
        #expect(MenuBarAppearance.accessibilityLabel(percent: 75, state: .onBattery(timeLeft: 5 * 3600 + 30 * 60))
            == "Battery 75 percent, about 5 hours 30 minutes left")
        #expect(MenuBarAppearance.accessibilityLabel(percent: 80, state: .charging(timeToFull: 3600 + 10 * 60))
            == "Battery 80 percent, charging, 1 hour 10 minutes to full")
        #expect(MenuBarAppearance.accessibilityLabel(percent: 100, state: .pluggedIn)
            == "Battery 100 percent, plugged in")
        #expect(MenuBarAppearance.accessibilityLabel(percent: 40, state: onBattery)
            == "Battery 40 percent, on battery")
        #expect(MenuBarAppearance.accessibilityLabel(percent: 80, state: .charging(timeToFull: nil))
            == "Battery 80 percent, charging")
    }

    @Test func spelledDurations() {
        #expect(MenuBarAppearance.spelledDuration(3600) == "1 hour")
        #expect(MenuBarAppearance.spelledDuration(2 * 3600) == "2 hours")
        #expect(MenuBarAppearance.spelledDuration(60 * 5) == "5 minutes")
        #expect(MenuBarAppearance.spelledDuration(30 * 60) == "30 minutes")
        #expect(MenuBarAppearance.spelledDuration(3600 + 5 * 60) == "1 hour 5 minutes")
        #expect(MenuBarAppearance.spelledDuration(2 * 3600 + 60) == "2 hours")
        #expect(MenuBarAppearance.spelledDuration(60) == "less than 5 minutes")
        #expect(MenuBarAppearance.spelledDuration(0) == "less than 5 minutes")
        #expect(MenuBarAppearance.spelledDuration(-30) == "less than 5 minutes")
    }

    @Test func spelledDurationIsCapped() {
        #expect(MenuBarAppearance.spelledDuration(200 * 3600) == "99 hours")
    }
}
