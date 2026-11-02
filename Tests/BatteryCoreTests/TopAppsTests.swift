import Testing
@testable import BatteryCore

@Suite struct TopAppsTests {
    @Test func ranksByPower() {
        let rows: [(name: String, power: Double)] = [("Mail", 2), ("Safari", 9), ("Xcode", 5)]
        #expect(TopApps.names(from: rows, limit: 2) == ["Safari", "Xcode"])
    }

    @Test func mergesDuplicateNamesBeforeRanking() {
        let rows: [(name: String, power: Double)] = [
            ("Safari", 4), ("Xcode", 6), ("Safari", 3), ("Mail", 1),
        ]
        #expect(TopApps.names(from: rows, limit: 2) == ["Safari", "Xcode"])
    }

    @Test func skipsEmptyNames() {
        let rows: [(name: String, power: Double)] = [("", 50), ("Mail", 2), ("Notes", 1)]
        #expect(TopApps.names(from: rows, limit: 2) == ["Mail", "Notes"])
    }

    @Test func fewerRowsThanLimit() {
        #expect(TopApps.names(from: [("Mail", 2)], limit: 2) == ["Mail"])
        #expect(TopApps.names(from: [], limit: 2).isEmpty)
    }

    @Test func tiesBreakByName() {
        let rows: [(name: String, power: Double)] = [("Zed", 3), ("Alpha", 3), ("Mid", 3)]
        #expect(TopApps.names(from: rows, limit: 2) == ["Alpha", "Mid"])
    }
}
