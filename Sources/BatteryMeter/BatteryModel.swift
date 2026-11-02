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

    private var retentionCutoff: Date {
        Date().addingTimeInterval(-TimeInterval(retentionDays) * 86_400)
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

    /// Loads the retention window once (off the main actor) and prunes the file once.
    func loadHistory() async {
        let store = self.store
        let cutoff = retentionCutoff
        let loaded = await Task.detached(priority: .utility) {
            let readings = store.load(since: cutoff)
            try? store.prune(olderThan: cutoff)
            return (readings, FullChargeLearner.estimate(history: readings, current: nil, liveWatts: nil))
        }.value
        history = loaded.0
        learned = loaded.1
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
        try? store.reset()
        history = []
        learned = nil
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
