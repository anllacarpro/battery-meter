import Foundation
import Observation
import BatteryCore

/// Builds `BatteryReport` off the main thread from a snapshot of the battery history, the
/// cached `pmset` log and the stored app energy. Rebuilds at most every 300 s unless
/// forced; re-reads `pmset` at most every 1800 s.
@MainActor @Observable
final class ReportsModel {
    static let rebuildInterval: TimeInterval = 300
    static let powerLogInterval: TimeInterval = 1800

    var report: BatteryReport?

    @ObservationIgnored private let battery: BatteryModel
    @ObservationIgnored private let energyStore: AppEnergyStore
    @ObservationIgnored private let logSource: PowerLogSource
    @ObservationIgnored private var lastBuild: Date?
    @ObservationIgnored private var powerLog: (text: String, fetched: Date)?
    /// Bumped by every build and by reset; a build that finishes under an older
    /// generation is stale and discarded, so it never overwrites a newer one.
    @ObservationIgnored private var generation = 0

    init(battery: BatteryModel, energyStore: AppEnergyStore, logSource: PowerLogSource) {
        self.battery = battery
        self.energyStore = energyStore
        self.logSource = logSource
    }

    func refresh(force: Bool = false) {
        let now = Date()
        // A clock set back (now before the last build) counts as due.
        if !force, let last = lastBuild, now >= last, now.timeIntervalSince(last) < Self.rebuildInterval {
            return
        }
        lastBuild = now
        generation += 1
        let gen = generation
        let history = battery.history
        let store = energyStore
        let logSource = self.logSource
        let cached = powerLog
        let logIsFresh = cached.map { now >= $0.fetched && now.timeIntervalSince($0.fetched) < Self.powerLogInterval } ?? false

        Task {
            var logText = cached?.text
            if !logIsFresh, let fresh = await logSource.read() {
                logText = fresh
                self.powerLog = (fresh, Date())
            }
            let text = logText
            let built = await Task.detached(priority: .utility) {
                BatteryReport.build(
                    history: history, powerEvents: SleepLog.parse(text ?? ""),
                    appEnergy: store.load(), now: now, calendar: .current)
            }.value
            guard gen == self.generation else { return }
            self.report = built
        }
    }

    /// Called after "Reset learned data": drops the report and any build in flight, and
    /// clears the throttle so the next `refresh` rebuilds from the emptied stores. The
    /// `pmset` cache is system data, not learned data, so it is kept.
    func handleReset() {
        generation += 1
        report = nil
        lastBuild = nil
    }
}
