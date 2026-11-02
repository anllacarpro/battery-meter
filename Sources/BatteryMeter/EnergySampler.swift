import AppKit
import BatteryCore

/// Every 300 s on battery, samples per-process power with `top` and adds each app's energy
/// impact (power x 300 s) to today's totals in `AppEnergyStore`. Plugged in, it does nothing.
/// No admin rights are needed, and app names stay on the Mac. App Nap is held off by the
/// activity `BatteryModel.start()` holds for the app's lifetime.
@MainActor
final class EnergySampler {
    static let interval: TimeInterval = 300

    private let battery: BatteryModel
    private let store: AppEnergyStore
    private var timer: Timer?
    private var sampling = false
    /// Bumped by `handleReset()`; a sample taken before a reset is dropped, not written.
    private var generation = 0

    init(battery: BatteryModel, store: AppEnergyStore) {
        self.battery = battery
        self.store = store
    }

    /// The first sample lands at the first tick, 300 s after start.
    func start() {
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
    }

    /// One tick: skipped unless on battery (and while a previous tick is still running).
    func sampleNow() async {
        guard !sampling, battery.reading?.externalConnected == false else { return }
        sampling = true
        defer { sampling = false }
        let gen = generation

        let rows = await Self.readTop()
        guard !rows.isEmpty else { return }
        var impacts: [String: Double] = [:]
        for row in rows {
            let name = NSRunningApplication(processIdentifier: row.pid)?.localizedName ?? row.command
            impacts[name, default: 0] += row.power * Self.interval
        }

        guard gen == generation else { return }
        let now = Date()
        let day = AppEnergyReport.dayKey(for: now, calendar: .current)
        let store = self.store
        await Task.detached(priority: .utility) {
            try? store.add(impacts, on: day, now: now)
        }.value
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
