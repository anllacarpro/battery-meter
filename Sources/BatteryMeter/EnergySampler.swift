import AppKit
import Observation
import BatteryCore

/// 20 s after launch and then every 300 s on battery, samples per-process power with `top` and adds each app's energy
/// impact (power x 300 s) to today's totals in `AppEnergyStore`. Plugged in, it does nothing.
/// No admin rights are needed, and app names stay on the Mac. App Nap is held off by the
/// activity `BatteryModel.start()` holds for the app's lifetime. Each sample also records
/// the two apps drawing the most power, for the menu.
@MainActor @Observable
final class EnergySampler {
    static let interval: TimeInterval = 300
    static let firstSampleDelay: TimeInterval = 20
    /// `topApps` is shown only while the sample is younger than this.
    static let topAppsMaxAge: TimeInterval = 600
    static let topAppsLimit = 2

    /// Up to two names from the latest sample, highest power first.
    private(set) var topApps: [String] = []
    private(set) var topAppsDate: Date?

    @ObservationIgnored private let battery: BatteryModel
    @ObservationIgnored private let store: AppEnergyStore
    @ObservationIgnored private var firstTimer: Timer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sampling = false
    /// Bumped by `handleReset()`; a sample taken before a reset is dropped, not written.
    @ObservationIgnored private var generation = 0

    init(battery: BatteryModel, store: AppEnergyStore) {
        self.battery = battery
        self.store = store
    }

    /// The first sample lands 20 s after start, then every 300 s.
    func start() {
        guard firstTimer == nil, timer == nil else { return }
        let firstTimer = Timer(timeInterval: Self.firstSampleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.firstTimer = nil
                Task { await self.sampleNow() }
                self.startRepeating()
            }
        }
        firstTimer.tolerance = 2
        RunLoop.main.add(firstTimer, forMode: .common)
        self.firstTimer = firstTimer
    }

    private func startRepeating() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.sampleNow() }
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func handleReset() {
        generation += 1
        topApps = []
        topAppsDate = nil
    }

    /// The latest top apps, or none once the sample is 600 s old.
    func freshTopApps(now: Date) -> [String] {
        guard let date = topAppsDate, now.timeIntervalSince(date) < Self.topAppsMaxAge else { return [] }
        return topApps
    }

    #if DEBUG
    /// Snapshot rendering only: shows `topApps` as if sampled at `date`. Never samples or writes.
    func showSnapshot(topApps: [String], date: Date) {
        self.topApps = topApps
        topAppsDate = date
    }
    #endif

    /// One tick: skipped unless on battery (and while a previous tick is still running).
    func sampleNow() async {
        guard !sampling, battery.reading?.externalConnected == false else { return }
        sampling = true
        defer { sampling = false }
        let gen = generation

        let rows = await Self.readTop()
        guard !rows.isEmpty else { return }
        var impacts: [String: Double] = [:]
        var named: [(name: String, power: Double)] = []
        for row in rows {
            // A localized name that is only marks falls back to the process name.
            let localized = AppEnergyReport.cleanName(
                NSRunningApplication(processIdentifier: row.pid)?.localizedName ?? "")
            let name = localized.isEmpty ? AppEnergyReport.cleanName(row.command) : localized
            guard !name.isEmpty else { continue }
            impacts[name, default: 0] += row.power * Self.interval
            named.append((name: name, power: row.power))
        }

        guard gen == generation else { return }
        let now = Date()
        topApps = TopApps.names(from: named, limit: Self.topAppsLimit)
        topAppsDate = now
        let day = AppEnergyReport.dayKey(for: now, calendar: .current)
        let store = self.store
        await Task.detached(priority: .utility) {
            try? store.add(impacts, on: day, now: now)
        }.value
        // A reset that landed during the write ran before (or alongside) it, so the sample
        // may have reached the emptied file: clear it again, still off the main thread.
        if gen != generation {
            await Task.detached(priority: .utility) {
                try? store.reset()
            }.value
        }
    }

    /// Two `top` samples one second apart, sorted by power; only the second has deltas.
    /// Any failure gives no rows. Runs and parses off the main actor.
    private static func readTop() async -> [ProcessPower] {
        await Task.detached(priority: .utility) {
            guard let data = await ProcessRunner.run(
                "/usr/bin/top", ["-l", "2", "-s", "1", "-o", "power", "-stats", "pid,command,power", "-n", "20"])
            else { return [] }
            return TopEnergyParser.parse(String(decoding: data, as: UTF8.self))
        }.value
    }
}
