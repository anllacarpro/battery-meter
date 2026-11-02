import Testing
import Foundation
@testable import BatteryCore

@Suite struct SleepReportTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z")!

    // Lines copied from a real `pmset -g log`; fields are separated by spaces and a tab.
    var fixture: String {
        [
            "2026-11-01 21:10:31 -0500 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:50%) 307 secs",
            "2026-11-01 21:10:32 -0500 Wake Requests       \t[process=dasd request=SleepService deltaSecs=952]",
            "2026-11-01 21:15:38 -0500 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty centauri-alpha E_TKO_NO_RESPONSE ARPT/ Using BATT (Charge:50%) 5 secs",
            "2026-11-01 21:19:48 -0500 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty RTP.multi-touch/HID Activity Using BATT (Charge:50%)",
            "2026-10-31 15:48:11 -0500 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using AC (Charge:99%) 5 secs",
        ].joined(separator: "\n")
    }

    func event(_ hoursAgo: Double, _ kind: PowerEvent.Kind, battery: Bool = true, charge: Int = 80,
               reason: WakeReason? = nil) -> PowerEvent {
        PowerEvent(date: now.addingTimeInterval(-hoursAgo * 3600), kind: kind,
                   onBattery: battery, charge: charge, reason: reason)
    }

    @Test func parsesOwnerLines() {
        let events = SleepLog.parse(fixture)
        #expect(events.count == 4)
        #expect(events.map(\.kind) == [.sleep, .darkWake, .wake, .sleep])
        #expect(events[0].onBattery && events[0].charge == 50 && events[0].reason == nil)
        #expect(events[1].reason == .network)
        #expect(events[2].reason == .lid)
        #expect(events[3].onBattery == false && events[3].charge == 99)
    }

    @Test func garbledLineSkipped() {
        let text = "2026-11-01 21:10:31 -0500 Sleep               \tEntering Sleep state due to 'Idle Sleep' 5 secs"
        #expect(SleepLog.parse(text).isEmpty)
    }

    @Test func reasonCategories() {
        func reason(_ r: String) -> WakeReason? {
            let line = "2026-11-01 21:19:48 -0500 Wake                \tWake from Deep Idle : due to \(r) Using BATT (Charge:50%)"
            return SleepLog.parse(line).first?.reason
        }
        #expect(reason("EC.LidOpen lid") == .lid)
        #expect(reason("collid") == .other)
        #expect(reason("EC.PowerButton pwrbtn") == .powerButton)
        #expect(reason("USB HID Activity") == .userInput)
        #expect(reason("en0 something") == .network)
        #expect(reason("RTC (Alarm)") == .scheduled)
        #expect(reason("mystery") == .other)
    }

    @Test func periodWithDrain() {
        let events = [event(9, .sleep, charge: 80), event(1, .wake, charge: 76, reason: .lid)]
        let report = SleepReport.build(events: events, now: now)
        #expect(report.periods.count == 1)
        #expect(report.periods[0].percentLost == 4)
        #expect(report.periods[0].darkWakes == 0)
        #expect(report.percentPerHour == 0.5)
    }

    @Test func darkWakesCountedAndPeriodsNewestFirst() {
        let events = [
            event(30, .sleep, charge: 90), event(28, .darkWake, charge: 89, reason: .network),
            event(26, .wake, charge: 88, reason: .lid),
            event(10, .sleep, charge: 70), event(5, .wake, charge: 75, reason: .lid),
        ]
        let report = SleepReport.build(events: events, now: now)
        #expect(report.periods.count == 2)
        #expect(report.periods[0].start > report.periods[1].start)
        #expect(report.periods[0].percentLost == 0)   // charge rose; clamped
        #expect(report.periods[1].darkWakes == 1)
        #expect(report.periods[1].percentLost == 2)
    }

    @Test func acPeriodExcluded() {
        let events = [event(9, .sleep, charge: 80), event(5, .darkWake, battery: false, charge: 80, reason: .scheduled),
                      event(1, .wake, charge: 79, reason: .lid)]
        let report = SleepReport.build(events: events, now: now)
        #expect(report.periods.isEmpty)
        #expect(report.percentPerHour == nil)
    }

    @Test func shortPeriodExcluded() {
        let events = [event(2, .sleep), event(2 - 10.0 / 60, .wake, reason: .lid)]
        #expect(SleepReport.build(events: events, now: now).periods.isEmpty)
    }

    @Test func unfinishedSleepDropped() {
        let events = [event(5, .sleep)]
        #expect(SleepReport.build(events: events, now: now).periods.isEmpty)
    }

    @Test func oldPeriodExcluded() {
        let events = [event(24 * 8 + 5, .sleep), event(24 * 8, .wake, reason: .lid)]
        #expect(SleepReport.build(events: events, now: now).periods.isEmpty)
    }

    @Test func reasonsCountedDescending() {
        let events = [
            event(20, .wake, reason: .lid), event(19, .darkWake, reason: .network),
            event(18, .darkWake, reason: .network), event(17, .darkWake, reason: .network),
            event(16, .wake, reason: .userInput), event(15, .wake, reason: .userInput),
            event(24 * 9, .wake, reason: .scheduled),   // outside 7 days
        ]
        let report = SleepReport.build(events: events, now: now)
        #expect(report.wakeReasons == [
            WakeReasonCount(reason: .network, count: 3),
            WakeReasonCount(reason: .userInput, count: 2),
            WakeReasonCount(reason: .lid, count: 1),
        ])
    }

    @Test func darkWakeSleepChainIsOnePeriod() {
        var events = [event(10, .sleep, charge: 66)]
        for i in 1...5 {
            events.append(event(10 - Double(i) * 0.5, .darkWake, charge: 66))
            events.append(event(10 - Double(i) * 0.5 + 0.01, .sleep, charge: 66))
        }
        events.append(event(1, .wake, charge: 64, reason: .lid))
        let report = SleepReport.build(events: events, now: now)
        #expect(report.periods.count == 1)
        #expect(report.periods[0].darkWakes == 5)
        #expect(report.periods[0].percentLost == 2)
    }
}
