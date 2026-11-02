import Foundation
import Testing
@testable import BatteryCore

@Suite struct MenuBarTextTests {
    private let sixForty: TimeInterval = 6 * 3600 + 40 * 60

    @Test func onBatteryWithHours() {
        let state = PowerState.onBattery(timeLeft: sixForty)
        #expect(MenuBarText.text(state: state, percent: 34, format: .hours) == "6h 40m")
        #expect(MenuBarText.text(state: state, percent: 34, format: .percent) == "34%")
        #expect(MenuBarText.text(state: state, percent: 34, format: .both) == "6h 40m · 34%")
    }

    @Test func chargingWithTimeToFull() {
        let state = PowerState.charging(timeToFull: 45 * 60)
        #expect(MenuBarText.text(state: state, percent: 80, format: .hours) == "45m")
        #expect(MenuBarText.text(state: state, percent: 80, format: .percent) == "80%")
        #expect(MenuBarText.text(state: state, percent: 80, format: .both) == "45m · 80%")
    }

    @Test(arguments: [MenuBarFormat.hours, .both])
    func withoutHoursHoursFormatsFallBack(format: MenuBarFormat) {
        #expect(MenuBarText.text(state: .onBattery(timeLeft: nil), percent: 34, format: format) == "—")
        #expect(MenuBarText.text(state: .charging(timeToFull: nil), percent: 80, format: format) == "80%")
        #expect(MenuBarText.text(state: .pluggedIn, percent: 100, format: format) == "100%")
    }

    @Test func percentAlwaysShowsPercent() {
        #expect(MenuBarText.text(state: .onBattery(timeLeft: nil), percent: 34, format: .percent) == "34%")
        #expect(MenuBarText.text(state: .charging(timeToFull: nil), percent: 80, format: .percent) == "80%")
        #expect(MenuBarText.text(state: .pluggedIn, percent: 100, format: .percent) == "100%")
    }

    @Test func rawValuesMatchStoredDefaults() {
        #expect(MenuBarFormat.allCases.map(\.rawValue) == ["hours", "percent", "both", "watts", "none"])
    }
}
