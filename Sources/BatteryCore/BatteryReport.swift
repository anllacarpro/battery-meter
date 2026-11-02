import Foundation

/// Every report the Reports view shows, built in one pass from already-collected inputs.
/// Pure: no I/O, so it can run on any thread.
public struct BatteryReport: Equatable, Sendable {
    public var generated: Date
    public var usage: UsageReport
    public var sessions: [DischargeSession]          // newest first
    public var charging: ChargingReport
    public var health: HealthTrend
    public var sleep: SleepReport
    public var apps: [AppShare]

    public init(generated: Date, usage: UsageReport, sessions: [DischargeSession],
                charging: ChargingReport, health: HealthTrend, sleep: SleepReport, apps: [AppShare]) {
        self.generated = generated
        self.usage = usage
        self.sessions = sessions
        self.charging = charging
        self.health = health
        self.sleep = sleep
        self.apps = apps
    }

    public static func build(history: [BatteryReading], powerEvents: [PowerEvent],
                             appEnergy: [String: [String: Double]], now: Date, calendar: Calendar) -> BatteryReport {
        BatteryReport(
            generated: now,
            usage: UsageReport.build(history: history, now: now, calendar: calendar),
            sessions: FullChargeLearner.sessions(in: history).reversed(),
            charging: ChargingReport.build(history: history, now: now),
            health: HealthTrend.build(points: DailyHealth.points(in: history)),
            sleep: SleepReport.build(events: powerEvents, now: now),
            apps: AppEnergyReport.build(days: appEnergy, now: now, calendar: calendar))
    }
}
