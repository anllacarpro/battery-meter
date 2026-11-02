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
