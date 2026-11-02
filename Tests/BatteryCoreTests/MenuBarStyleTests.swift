import Foundation
import Testing
@testable import BatteryCore

@Suite struct MenuBarStyleTests {
    private func defaults() -> UserDefaults {
        let name = "MenuBarStyleTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func standardStyleIsToday() {
        let s = MenuBarStyle.standard
        #expect(s.icon == .symbol && s.format == .hours && s.colors == .lowOnly)
        #expect(s.lowThreshold == 10 && s.timeStyle == .hoursMinutes)
        #expect(MenuBarStyle(defaults: defaults()) == .standard)
    }

    @Test func styleReadsDefaults() {
        let d = defaults()
        d.set("percentInside", forKey: "menuBarIcon")
        d.set("watts", forKey: "menuBarFormat")
        d.set("lowAndCharging", forKey: "menuBarColors")
        d.set(15, forKey: "menuBarLowThreshold")
        d.set("clock", forKey: "menuBarTimeStyle")
        #expect(MenuBarStyle(defaults: d) == MenuBarStyle(
            icon: .percentInside, format: .watts, colors: .lowAndCharging, lowThreshold: 15, timeStyle: .clock))
    }

    @Test func invalidValuesFallBack() {
        let d = defaults()
        d.set("bogus", forKey: "menuBarIcon")
        d.set(3, forKey: "menuBarFormat")
        d.set("", forKey: "menuBarColors")
        d.set(7, forKey: "menuBarLowThreshold")
        d.set("x", forKey: "menuBarTimeStyle")
        #expect(MenuBarStyle(defaults: d) == .standard)
    }

    @Test func clockStyle() {
        #expect(DurationText.clock(23_400) == "6:30")
        #expect(DurationText.clock(2_700) == "0:45")
        let state = PowerState.onBattery(timeLeft: 23_400)
        #expect(MenuBarText.text(state: state, percent: 34, format: .hours, timeStyle: .clock) == "6:30")
        #expect(MenuBarText.text(state: state, percent: 34, format: .both, timeStyle: .clock) == "6:30 · 34%")
    }

    @Test func wattsText() {
        let state = PowerState.onBattery(timeLeft: 3600)
        #expect(MenuBarText.text(state: state, percent: 34, format: .watts, watts: 26.6) == "26.6 W")
        #expect(MenuBarText.text(state: state, percent: 34, format: .watts, watts: nil) == "—")
    }

    @Test func noneFormatIsEmpty() {
        #expect(MenuBarText.text(state: .pluggedIn, percent: 100, format: .none).isEmpty)
    }

    @Test func noIconAndNoTextFallsBackToSymbol() {
        var s = MenuBarStyle.standard
        s.icon = .none
        s.format = .none
        #expect(s.effectiveIcon == .symbol)
        s.format = .percent
        #expect(s.effectiveIcon == .none)
        s.icon = .percentInside
        s.format = .none
        #expect(s.effectiveIcon == .percentInside)
    }

    @Test func colorRoles() {
        let battery = PowerState.onBattery(timeLeft: nil)
        let charging = PowerState.charging(timeToFull: nil)
        var s = MenuBarStyle.standard
        #expect(MenuBarAppearance.colorRole(percent: 10, state: battery, style: s) == .low)
        #expect(MenuBarAppearance.colorRole(percent: 11, state: battery, style: s) == .none)
        #expect(MenuBarAppearance.colorRole(percent: 10, state: charging, style: s) == .none)
        #expect(MenuBarAppearance.colorRole(percent: 50, state: charging, style: s) == .none)
        s.colors = .lowAndCharging
        #expect(MenuBarAppearance.colorRole(percent: 50, state: charging, style: s) == .charging)
        s.colors = .monochrome
        #expect(MenuBarAppearance.colorRole(percent: 3, state: battery, style: s) == .none)
        s.colors = .lowOnly
        s.lowThreshold = 20
        #expect(MenuBarAppearance.colorRole(percent: 20, state: battery, style: s) == .low)
        #expect(MenuBarAppearance.isLow(percent: 20, state: battery, threshold: 20))
    }
}
