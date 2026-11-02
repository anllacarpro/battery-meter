import Foundation

/// Per-day, per-app energy impact totals, stored as JSON:
/// `[dayKey "yyyy-MM-dd": [appName: impactSeconds]]`. Days older than 30 are pruned on `add`.
/// File access is serialized on a private queue; the struct is Sendable because its
/// stored properties (a URL and a DispatchQueue) both are.
public struct AppEnergyStore: Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "BatteryCore.AppEnergyStore")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatteryMeter", isDirectory: true)
            .appendingPathComponent("app-energy.json")
    }

    private static let retentionDays = 30

    /// Merge-adds `impacts` into `day`, prunes days older than 30 relative to `day`, and
    /// (or today, if earlier) and writes atomically. Throws if the file exists but cannot be read (so existing days
    /// are never overwritten by a transient error). A missing file starts empty; an
    /// undecodable file is replaced.
    public func add(_ impacts: [String: Double], on day: String, now: Date = Date()) throws {
        try queue.sync {
            var days = try readExisting()
            var today = days[day] ?? [:]
            for (app, value) in impacts { today[app, default: 0] += value }
            days[day] = today
            // Prune relative to the earlier of `day` and today, so a far-future day (clock
            // skew) cannot wipe valid history.
            let todayKey = AppEnergyReport.dayKey(for: now, calendar: .current)
            if let cutoff = Self.cutoffKey(for: min(day, todayKey)) {
                days = days.filter { $0.key >= cutoff }
            }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(days).write(to: fileURL, options: .atomic)
        }
    }

    public func load() -> [String: [String: Double]] {
        queue.sync { (try? readExisting()) ?? [:] }
    }

    public func reset() throws {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Must be called on `queue`. Missing file -> `[:]`; read error -> throws;
    /// undecodable content -> `[:]`.
    private func readExisting() throws -> [String: [String: Double]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        return (try? JSONDecoder().decode([String: [String: Double]].self, from: data)) ?? [:]
    }

    /// The oldest day key to keep: `day` minus 30 days. Keys are plain calendar dates, so UTC
    /// is only a neutral frame; the format comes from the shared day-key formatter.
    private static func cutoffKey(for day: String) -> String? {
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let f = AppEnergyReport.makeDayFormatter(timeZone: utc)
        guard let date = f.date(from: day),
              let cutoff = cal.date(byAdding: .day, value: -retentionDays, to: date) else { return nil }
        return f.string(from: cutoff)
    }
}
