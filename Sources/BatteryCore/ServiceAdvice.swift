import Foundation

/// Whether the battery looks like it needs attention. Low health wins over high cycles.
public enum ServiceAdvice: Equatable, Sendable {
    case none
    case lowHealth
    case highCycles

    /// Health below this is Apple's service threshold.
    static let healthThreshold = 80.0
    /// Fraction of the rated cycle count at which to warn.
    static let cycleFraction = 0.8

    public static func advice(for reading: BatteryReading) -> ServiceAdvice {
        if reading.healthPercent < healthThreshold { return .lowHealth }
        if let limit = reading.designCycleCount, limit > 0,
           Double(reading.cycleCount) >= Double(limit) * cycleFraction {
            return .highCycles
        }
        return .none
    }

    public var message: String? {
        switch self {
        case .none: nil
        case .lowHealth: "Health is below 80%, Apple's service threshold. Consider a battery service."
        case .highCycles: "This battery is near its rated cycle count. Health may start to drop faster."
        }
    }
}
