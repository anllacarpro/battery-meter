import Foundation
import Observation
import BatteryCore

@MainActor @Observable
final class BatteryModel {
    static let readInterval: TimeInterval = 10
    static let recordInterval: TimeInterval = 60
    static let defaultRetentionDays = 180

    var reading: BatteryReading?
    var state: PowerState?
    var liveWatts: Double?
    var liveVolts: Double?
    var liveAmps: Double?
    var fullCharge: FullChargeEstimate?
    var history: [BatteryReading] = []

    @ObservationIgnored private let source = IOKitBatterySource()
    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private var estimator = PowerEstimator()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var historyLoaded = false
    /// Days of history `history` currently covers (0 until the first load lands).
    @ObservationIgnored private var coveredDays = 0
    /// Bumped by reset and retention changes; a load that finishes under an older
    /// generation is stale and discarded, so it can never overwrite a reset.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastRecorded: Date?
    /// Estimate learned from discharge sessions in `history`; recomputed only when history changes.
    @ObservationIgnored private var learned: FullChargeEstimate?

    init(store: HistoryStore = HistoryStore(fileURL: HistoryStore.defaultURL)) {
        self.store = store
    }

    private var retentionDays: Int {
        let days = UserDefaults.standard.integer(forKey: "retentionDays")
        return days > 0 ? days : Self.defaultRetentionDays
    }

    private var retentionCutoff: Date { Self.cutoff(days: retentionDays) }

    private static func cutoff(days: Int) -> Date {
        Date().addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    func start() {
        guard timer == nil else { return }
        refresh(record: true)
        let timer = Timer(timeInterval: Self.readInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(record: true) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await loadHistory() }
    }

    /// Loads the retention window (off the main actor) and, when `pruning`, prunes the
    /// file once. Snapshot rendering passes `false` so the file is never rewritten.
    func loadHistory(pruning: Bool = true) async {
        await load(days: retentionDays, pruning: pruning)
    }

    /// Applies a new history window without a restart. Shrinking trims memory only (the
    /// file is pruned at the next launch); growing reloads the wider window from disk.
    func applyRetention(days: Int) {
        generation += 1
        if historyLoaded, days <= coveredDays {
            coveredDays = days
            let cutoff = Self.cutoff(days: days)
            history.removeAll { $0.timestamp < cutoff }
            learned = FullChargeLearner.estimate(history: history, current: nil, liveWatts: nil)
            updateFullCharge()
        } else {
            Task { await load(days: days, pruning: false) }
        }
    }

    private func load(days: Int, pruning: Bool) async {
        let store = self.store
        let cutoff = Self.cutoff(days: days)
        let gen = generation
        let loaded = await Task.detached(priority: .utility) {
            let readings = store.load(since: cutoff)
            if pruning { try? store.prune(olderThan: cutoff) }
            return (readings, FullChargeLearner.estimate(history: readings, current: nil, liveWatts: nil))
        }.value
        guard gen == generation else { return }
        // A reload can race the recorder: keep readings appended after the file was read.
        let lastLoaded = loaded.0.last?.timestamp ?? .distantPast
        let recorded = history.filter { $0.timestamp > lastLoaded }
        history = loaded.0 + recorded
        learned = recorded.isEmpty
            ? loaded.1
            : FullChargeLearner.estimate(history: history, current: nil, liveWatts: nil)
        coveredDays = days
        historyLoaded = true
        updateFullCharge()
    }

    func refresh(record: Bool) {
        let now = Date()
        guard let raw = source.readRaw(), let reading = BatteryParser.parse(raw, at: now) else {
            reading = nil
            state = nil
            liveWatts = nil
            liveVolts = nil
            liveAmps = nil
            fullCharge = nil
            return
        }
        self.reading = reading
        state = estimator.update(with: reading)
        liveWatts = estimator.liveWatts
        liveVolts = estimator.liveVolts
        liveAmps = estimator.liveAmps

        // Recording waits for the initial load so nothing is read back twice.
        if record, historyLoaded,
           lastRecorded.map({ now.timeIntervalSince($0) >= Self.recordInterval - 1 }) ?? true {
            lastRecorded = now
            try? store.append(reading)
            history.append(reading)
            let cutoff = retentionCutoff
            if let first = history.first, first.timestamp < cutoff {
                history.removeAll { $0.timestamp < cutoff }
            }
            learned = FullChargeLearner.estimate(history: history, current: nil, liveWatts: nil)
        }
        updateFullCharge()
    }

    func resetLearnedData() {
        generation += 1
        try? store.reset()
        history = []
        learned = nil
        // The empty history is now authoritative, even if the initial load never landed.
        coveredDays = retentionDays
        historyLoaded = true
        updateFullCharge()
    }

    /// Learned sessions win; otherwise fall back to full capacity / live draw, which only
    /// means something while the battery is the power source.
    private func updateFullCharge() {
        let onBattery = reading.map { !$0.externalConnected } ?? false
        fullCharge = learned ?? FullChargeLearner.estimate(
            history: [], current: reading, liveWatts: onBattery ? liveWatts : nil)
    }
}
