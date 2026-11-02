import Foundation

/// Every report the Reports view shows, built in one pass from already-collected inputs.
/// Pure: no I/O, so it can run on any thread.
public struct BatteryReport: Equatable, Sendable {
    public var generated: Date
    public var usage: UsageReport
    public var sessions: [DischargeSession]          // newest first
    public var charging: ChargingReport
    public var health: HealthTrend
    public var healthPoints: [HealthPoint]           // daily health, oldest first; what `health` is fitted to
    /// `nil` when the sleep log couldn't be read: unknown, which is not the same as no sleep.
    public var sleep: SleepReport?
    public var apps: [AppShare]

    public init(generated: Date, usage: UsageReport, sessions: [DischargeSession],
                charging: ChargingReport, health: HealthTrend, healthPoints: [HealthPoint],
                sleep: SleepReport?, apps: [AppShare]) {
        self.generated = generated
        self.usage = usage
        self.sessions = sessions
        self.charging = charging
        self.health = health
        self.healthPoints = healthPoints
        self.sleep = sleep
        self.apps = apps
    }

    /// `powerEvents` is `nil` when the sleep log couldn't be read; `sleep` is then `nil` too.
    public static func build(history: [BatteryReading], powerEvents: [PowerEvent]?,
                             appEnergy: [String: [String: Double]], now: Date, calendar: Calendar) -> BatteryReport {
        let points = DailyHealth.points(in: history)
        return BatteryReport(
            generated: now,
            usage: UsageReport.build(history: history, now: now, calendar: calendar),
            sessions: FullChargeLearner.sessions(in: history).reversed(),
            charging: ChargingReport.build(history: history, now: now),
            health: HealthTrend.build(points: points),
            healthPoints: points,
            sleep: powerEvents.map { SleepReport.build(events: $0, now: now) },
            apps: AppEnergyReport.build(days: appEnergy, now: now, calendar: calendar))
    }
}
