import Testing
@testable import BatteryCore

@Suite struct QuickMenuTests {
    @Test func quickMenuOrderAndTitles() {
        let items = QuickMenu.items(format: .hours, launchAtLogin: false)
        #expect(items.map(\.title) == [
            "Open Battery Meter", "Reports…", "History…", "Health…", "",
            "Menu bar shows", "Launch at login", "Settings…", "", "Quit Battery Meter",
        ])
        #expect(items.map(\.isSeparator) == [
            false, false, false, false, true, false, false, false, true, false,
        ])
        #expect(items[5].children.map(\.title) == ["Hours left", "Percent", "Hours and percent", "Power draw", "Icon only"])
        #expect(items[5].children.map(\.action) == [
            .setFormat(.hours), .setFormat(.percent), .setFormat(.both), .setFormat(.watts), .setFormat(.none),
        ])
        #expect(items.map(\.action) == [
            .open, .reports, .history, .health, nil, nil, .toggleLaunchAtLogin, .settings, nil, .quit,
        ])
    }

    @Test(arguments: MenuBarFormat.allCases)
    func quickMenuChecksCurrentFormat(format: MenuBarFormat) {
        let items = QuickMenu.items(format: format, launchAtLogin: false)
        let checked = items[5].children.filter(\.isChecked)
        #expect(checked.count == 1)
        #expect(checked.first?.action == .setFormat(format))
    }

    @Test func launchToggleFollowsLaunchAtLogin() {
        let on = QuickMenu.items(format: .hours, launchAtLogin: true)
        let off = QuickMenu.items(format: .hours, launchAtLogin: false)
        #expect(on[6].isChecked)
        #expect(!off[6].isChecked)
    }

    @Test func updateNoticeLeadsTheMenuOnlyWhenThereIsOne() {
        let plain = QuickMenu.items(format: .hours, launchAtLogin: false)
        let withUpdate = QuickMenu.items(format: .hours, launchAtLogin: false, updateVersion: "0.1.4")
        #expect(withUpdate.first?.title == "Update available: 0.1.4…")
        #expect(withUpdate.first?.action == .showUpdate)
        #expect(withUpdate[1].isSeparator)
        #expect(Array(withUpdate.dropFirst(2)) == plain)
    }

    @Test func quickMenuKeys() {
        let items = QuickMenu.items(format: .hours, launchAtLogin: false)
        #expect(items[7].keyEquivalent == ",")
        #expect(items[9].keyEquivalent == "q")
        #expect(items[0].keyEquivalent == "")
    }
}
