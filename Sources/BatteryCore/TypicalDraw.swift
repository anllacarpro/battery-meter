import Foundation

/// The draw this Mac usually has on battery: the mean over the last week. The mean, not
/// the median, because spikes are real energy use and runtime follows the average draw.
public enum TypicalDraw {
    public static let minReadings = 30
    private static let window: TimeInterval = 7 * 24 * 3600

    public static func watts(in history: [BatteryReading], now: Date) -> Double? {
        let cutoff = now.addingTimeInterval(-window)
        let samples = history
            .filter { !$0.externalConnected && $0.timestamp >= cutoff && $0.timestamp <= now }
            .map(\.powerWatts)
        guard samples.count >= minReadings else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }
}
