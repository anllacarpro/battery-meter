import Foundation

/// Time left on battery, as a steady headline and as the current pace.
public struct RuntimeEstimate: Equatable, Sendable {
    /// Time left at the blended draw (typical and recent).
    public var headline: TimeInterval?
    /// Time left at the 30 s smoothed draw.
    public var atPace: TimeInterval?
    public var paceWatts: Double?
    public var typicalWatts: Double?
    /// True when no typical draw is known yet.
    public var isEstimate: Bool
    /// The current pace is at least 10 W and at least twice the typical draw.
    public var isHighUse: Bool

    public init(
        headline: TimeInterval?, atPace: TimeInterval?, paceWatts: Double?,
        typicalWatts: Double?, isEstimate: Bool, isHighUse: Bool
    ) {
        self.headline = headline
        self.atPace = atPace
        self.paceWatts = paceWatts
        self.typicalWatts = typicalWatts
        self.isEstimate = isEstimate
        self.isHighUse = isHighUse
    }
}
