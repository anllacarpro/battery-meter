import Foundation

/// The draw this Mac usually has on battery: the median over the last week.
public enum TypicalDraw {
    public static let minReadings = 30
    private static let window: TimeInterval = 7 * 24 * 3600

    public static func watts(in history: [BatteryReading], now: Date) -> Double? {
        let cutoff = now.addingTimeInterval(-window)
        let samples = history
            .filter { !$0.externalConnected && $0.timestamp >= cutoff && $0.timestamp <= now }
            .map(\.powerWatts)
            .sorted()
        guard samples.count >= minReadings else { return nil }
        let mid = samples.count / 2
        return samples.count.isMultiple(of: 2) ? (samples[mid - 1] + samples[mid]) / 2 : samples[mid]
    }
}
