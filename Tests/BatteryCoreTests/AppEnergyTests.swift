import Testing
import Foundation
@testable import BatteryCore

@Suite struct AppEnergyTests {
    private static let header = """
        Processes: 500 total, 3 running
        Load Avg: 2.0, 2.1, 2.2
        CPU usage: 5.0% user, 5.0% sys, 90.0% idle

        """

    private static let rows = """
        PID    COMMAND          POWER
        403    WindowServer     47.2
        88845  Claude Helper (R 11.7
        90630  top              6.3
        35686  WhatsApp         7.7

        """

    private static var twoSamples: String { header + rows + "\n" + header + rows }

    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppEnergyTests-\(UUID().uuidString)")
            .appendingPathComponent("sub/app-energy.json")
    }

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    // MARK: parser

    @Test func parsesSecondSample() {
        let out = TopEnergyParser.parse(Self.twoSamples)
        #expect(out.count == 3)
        #expect(!out.contains { $0.command == "top" })
        #expect(out[0] == ProcessPower(pid: 403, command: "WindowServer", power: 47.2))
        #expect(out[1].command == "Claude Helper (R")
        #expect(out[1].pid == 88845)
        #expect(out[1].power == 11.7)
    }

    @Test func emptyOutputIsEmpty() {
        #expect(TopEnergyParser.parse("").isEmpty)
        #expect(TopEnergyParser.parse(Self.header + Self.rows).isEmpty)
    }

    @Test func skipsZeroPowerAndStopsAtBlankLine() {
        let sample = """
            PID COMMAND POWER
            PID COMMAND POWER
            1 idle 0.0
            2 busy 3.5

            3 later 9.0
            """
        let out = TopEnergyParser.parse(sample)
        #expect(out == [ProcessPower(pid: 2, command: "busy", power: 3.5)])
    }

    @Test func nonFinitePowerRejected() {
        let sample = """
            PID COMMAND POWER
            PID COMMAND POWER
            1 infinite inf
            2 notnum nan
            3 fine 2.5

            """
        #expect(TopEnergyParser.parse(sample) == [ProcessPower(pid: 3, command: "fine", power: 2.5)])
    }

    // MARK: store

    @Test func farFutureDayDoesNotWipeHistory() throws {
        let store = AppEnergyStore(fileURL: makeURL())
        let now = Date(timeIntervalSince1970: 1_793_620_800) // 2026-11-02
        try store.add(["A": 1], on: "2026-10-30", now: now)
        try store.add(["A": 2], on: "2026-11-02", now: now)
        let future = AppEnergyReport.dayKey(for: now.addingTimeInterval(400 * 86_400), calendar: utc)
        try store.add(["A": 3], on: future, now: now)
        #expect(Set(store.load().keys) == ["2026-10-30", "2026-11-02", future])
    }

    @Test func storeMergesAndPrunes() throws {
        let store = AppEnergyStore(fileURL: makeURL())
        try store.add(["A": 1, "B": 2], on: "2026-01-01")
        try store.add(["A": 3], on: "2026-01-01")
        #expect(store.load() == ["2026-01-01": ["A": 4, "B": 2]])
        try store.add(["A": 5], on: "2026-02-01")   // 31 days later
        #expect(store.load() == ["2026-02-01": ["A": 5]])
    }

    @Test func storeKeepsThirtyDayBoundary() throws {
        let store = AppEnergyStore(fileURL: makeURL())
        try store.add(["A": 1], on: "2026-01-01")
        try store.add(["A": 1], on: "2026-01-31")   // exactly 30 days later
        #expect(Set(store.load().keys) == ["2026-01-01", "2026-01-31"])
    }

    @Test func missingFileLoadsEmptyAndResetRemoves() throws {
        let store = AppEnergyStore(fileURL: makeURL())
        #expect(store.load().isEmpty)
        try store.reset()   // no file: no throw
        try store.add(["A": 1], on: "2026-01-01")
        try store.reset()
        #expect(store.load().isEmpty)
    }

    @Test func corruptFileLoadsEmpty() throws {
        let url = makeURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json {".utf8).write(to: url)
        let store = AppEnergyStore(fileURL: url)
        #expect(store.load().isEmpty)
        // A corrupt file may be replaced by add.
        try store.add(["A": 2], on: "2026-01-01")
        #expect(store.load() == ["2026-01-01": ["A": 2]])
    }

    @Test func unreadableFileMakesAddThrowAndKeepsFile() throws {
        let url = makeURL()
        // A directory at the file path is present but cannot be read as data.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let store = AppEnergyStore(fileURL: url)
        #expect(store.load().isEmpty)
        #expect(throws: (any Error).self) { try store.add(["A": 1], on: "2026-01-01") }
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
    }

    // MARK: report

    @Test func dayKeyUsesCalendarTimeZone() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        // 2026-01-01 20:00 UTC is 2026-01-02 09:00 in Auckland (UTC+13).
        let d = Date(timeIntervalSince1970: 1_767_297_600)
        #expect(AppEnergyReport.dayKey(for: d, calendar: cal) == "2026-01-02")
        #expect(AppEnergyReport.dayKey(for: d, calendar: utc) == "2026-01-01")
    }

    @Test func dayKeyIgnoresNonGregorianCalendars() {
        let d = Date(timeIntervalSince1970: 1_793_620_800) // 2026-11-02 12:00 UTC
        for id in [Calendar.Identifier.buddhist, .japanese, .islamicUmmAlQura] {
            var cal = Calendar(identifier: id)
            cal.timeZone = TimeZone(identifier: "UTC")!
            #expect(AppEnergyReport.dayKey(for: d, calendar: cal) == "2026-11-02")
        }
    }

    @Test func reportTopEightShares() {
        let now = Date(timeIntervalSince1970: 1_767_225_600 + 12 * 3600) // 2026-01-01 12:00 UTC
        var today: [String: Double] = [:]
        for i in 1...12 { today["app\(i)"] = Double(i) }
        let days = [
            "2026-01-01": today,
            "2025-12-26": ["app1": 100],    // 6 days back: included
            "2025-12-25": ["old": 1000],    // 7 days back: excluded
        ]
        let shares = AppEnergyReport.build(days: days, now: now, calendar: utc)
        #expect(shares.count == 8)
        #expect(shares.first?.name == "app1")   // 1 + 100
        #expect(!shares.contains { $0.name == "old" })
        #expect(zip(shares, shares.dropFirst()).allSatisfy { $0.share >= $1.share })
        #expect(shares.reduce(0) { $0 + $1.share } <= 1.0 + 1e-9)
        let grand = 78.0 + 100
        #expect(abs(shares[0].share - 101 / grand) < 1e-9)
    }

    @Test func reportEmptyWhenNoEnergy() {
        #expect(AppEnergyReport.build(days: [:], now: Date(), calendar: utc).isEmpty)
        #expect(AppEnergyReport.build(days: ["x": ["A": 0]], now: Date(), calendar: utc).isEmpty)
    }

    @Test func cleanNameDropsInvisibleCharacters() {
        #expect(AppEnergyReport.cleanName("\u{200E}WhatsApp") == "WhatsApp")
        #expect(AppEnergyReport.cleanName("\u{2068}Safari\u{2069} ") == "Safari")
        #expect(AppEnergyReport.cleanName("  Claude Helper (R\n") == "Claude Helper (R")
        #expect(AppEnergyReport.cleanName("\u{200E} ").isEmpty)
        #expect(AppEnergyReport.cleanName("\u{FEFF}\u{202B}Notes\u{202C}\u{200F}") == "Notes")
    }

    @Test func cleanNameKeepsJoiners() {
        let zwj = "Dev\u{200D}Tools \u{200C}Beta"
        #expect(AppEnergyReport.cleanName("\u{2068}" + zwj + "\u{2069}") == zwj)
        #expect(AppEnergyReport.cleanName("\u{200D}x") == "\u{200D}x")
    }

    @Test func reportMergesNamesThatDifferOnlyByInvisibleCharacters() {
        let now = Date(timeIntervalSince1970: 1_767_225_600 + 12 * 3600) // 2026-01-01 12:00 UTC
        let days: [String: [String: Double]] = ["2026-01-01": ["\u{200E}WhatsApp": 1, "WhatsApp": 2, "Mail": 1, "\u{200E}": 5]]
        let shares = AppEnergyReport.build(days: days, now: now, calendar: utc)
        #expect(shares.map { $0.name } == ["WhatsApp", "Mail"])
        #expect(abs(shares[0].share - 0.75) < 1e-9)
    }
}
