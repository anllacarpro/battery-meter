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
    /// writes atomically. Throws if the file exists but cannot be read (so existing days
    /// are never overwritten by a transient error). A missing file starts empty; an
    /// undecodable file is replaced.
    public func add(_ impacts: [String: Double], on day: String) throws {
        try queue.sync {
            var days = try readExisting()
            var today = days[day] ?? [:]
            for (app, value) in impacts { today[app, default: 0] += value }
            days[day] = today
            if let cutoff = Self.cutoffKey(for: day) {
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

    /// The oldest day key to keep: `day` minus 30 days, using timezone-free date arithmetic
    /// (day keys are plain calendar dates, so UTC is only a neutral frame).
    private static func cutoffKey(for day: String) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day),
              let cutoff = cal.date(byAdding: .day, value: -retentionDays, to: date) else { return nil }
        return f.string(from: cutoff)
    }
}
