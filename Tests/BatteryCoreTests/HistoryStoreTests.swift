import Testing
import Foundation
@testable import BatteryCore

@Suite struct HistoryStoreTests {
    private func makeStore() -> (HistoryStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("sub/history.jsonl")
        return (HistoryStore(fileURL: url), url)
    }

    private func reading(_ t: TimeInterval, percent: Int = 50) -> BatteryReading {
        BatteryReading(
            timestamp: Date(timeIntervalSince1970: t), percent: percent,
            remainingCapacity: 2500, fullChargeCapacity: 5000, designCapacity: 5500,
            cycleCount: 100, designCycleCount: 1000, voltage: 12000, amperage: -1000,
            isCharging: false, externalConnected: false, fullyCharged: false)
    }

    private func append(raw: String, to url: URL) throws {
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(raw.utf8))
        try h.close()
    }

    @Test func appendThenLoad() throws {
        let (store, _) = makeStore()
        let rs = [reading(1_000_000), reading(1_000_060, percent: 49), reading(1_000_120, percent: 48)]
        for r in rs { try store.append(r) }
        #expect(store.load(since: .distantPast) == rs)
    }

    @Test func loadMissingFileIsEmpty() {
        let (store, _) = makeStore()
        #expect(store.load(since: .distantPast).isEmpty)
    }

    @Test func loadSinceFilters() throws {
        let (store, _) = makeStore()
        for t in [1_000_000.0, 1_000_100, 1_000_200] { try store.append(reading(t)) }
        let loaded = store.load(since: Date(timeIntervalSince1970: 1_000_100))
        #expect(loaded.map(\.timestamp.timeIntervalSince1970) == [1_000_100, 1_000_200])
    }

    @Test func truncatedLastLineSkipped() throws {
        let (store, url) = makeStore()
        try store.append(reading(1_000_000))
        try store.append(reading(1_000_060))
        try append(raw: "{\"timest", to: url)
        #expect(store.load(since: .distantPast).count == 2)
    }

    @Test func appendAfterTruncatedTailStartsFreshLine() throws {
        let (store, url) = makeStore()
        try store.append(reading(1_000_000))
        try append(raw: "{\"timest", to: url)
        try store.append(reading(1_000_060))
        let loaded = store.load(since: .distantPast)
        #expect(loaded.map(\.timestamp.timeIntervalSince1970) == [1_000_000, 1_000_060])
    }

    @Test func pruneRemovesOld() throws {
        let (store, url) = makeStore()
        for t in [1_000_000.0, 1_000_100, 1_000_200] { try store.append(reading(t)) }
        try append(raw: "{\"timest", to: url)
        try store.prune(olderThan: Date(timeIntervalSince1970: 1_000_100))
        #expect(store.load(since: .distantPast).map(\.timestamp.timeIntervalSince1970) == [1_000_100, 1_000_200])
        // still appendable afterwards
        try store.append(reading(1_000_300))
        #expect(store.load(since: .distantPast).count == 3)
    }

    @Test func pruneKeepsUndecodableCompleteLines() throws {
        let (store, url) = makeStore()
        try store.append(reading(1_000_000))
        try append(raw: "{\"future\":\"schema\"}\n", to: url)
        try store.append(reading(1_000_200))
        try store.prune(olderThan: Date(timeIntervalSince1970: 1_000_100))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("{\"future\":\"schema\"}\n"))
        #expect(store.load(since: .distantPast).map(\.timestamp.timeIntervalSince1970) == [1_000_200])
    }

    @Test func pruneDropsTruncatedTail() throws {
        let (store, url) = makeStore()
        try store.append(reading(1_000_200))
        try append(raw: "{\"timest", to: url)
        try store.prune(olderThan: Date(timeIntervalSince1970: 1_000_100))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("{\"timest\""))
        #expect(!text.hasSuffix("timest"))
        #expect(text.hasSuffix("\n"))
        #expect(store.load(since: .distantPast).count == 1)
    }

    @Test func pruneThrowsWhenUnreadable() throws {
        let (store, url) = makeStore()
        try store.append(reading(1_000_000))
        let original = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        #expect(throws: (any Error).self) {
            try store.prune(olderThan: Date(timeIntervalSince1970: 2_000_000))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func pruneMissingFileIsNoOp() throws {
        let (store, _) = makeStore()
        try store.prune(olderThan: Date())
        #expect(store.load(since: .distantPast).isEmpty)
    }

    @Test func resetEmpties() throws {
        let (store, _) = makeStore()
        try store.append(reading(1_000_000))
        try store.reset()
        #expect(store.load(since: .distantPast).isEmpty)
        try store.append(reading(1_000_060))
        #expect(store.load(since: .distantPast).count == 1)
    }

    @Test func resetMissingFileIsNoOp() throws {
        let (store, _) = makeStore()
        try store.reset()
    }
}
