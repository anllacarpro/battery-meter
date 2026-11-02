import SwiftUI
import Charts
import BatteryCore

// The six Reports sections, in spec order. Each renders only what `BatteryReport` holds
// and falls back to an empty state naming what it's waiting for.

private func emptyState(_ message: String, symbol: String) -> NotEnoughHistory {
    NotEnoughHistory(title: "Not enough data yet", message: message, symbol: symbol, compact: true)
}

/// Small secondary heading inside a card.
private struct SubHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

enum ReportFormat {
    static let sessionStart = Date.FormatStyle.dateTime
        .weekday(.abbreviated).month(.abbreviated).day().hour().minute()

    static func perHour(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%/hour"
    }
}

// MARK: - Usage

struct UsageSection: View {
    let usage: UsageReport
    /// Read here so a new reading redraws only this card; weeks that ended before the first
    /// recorded reading are hidden rather than shown as "0m".
    let battery: BatteryModel
    let hover: ChartHover

    var body: some View {
        ChartCard(title: "Usage", subtitle: "Time on battery each day, last 7 days") {
            if usage.hasData {
                VStack(alignment: .leading, spacing: 14) {
                    UsageChart(days: usage.days, recordedFrom: firstReading, hover: hover)
                        .frame(height: 150)
                    let weeks = recordedWeeks
                    VStack(alignment: .leading, spacing: 6) {
                        SubHeading(weeks.count == usage.weeks.count ? "Last \(weeks.count) weeks" : "By week")
                        HStack(spacing: 8) {
                            ForEach(weeks, id: \.week.start) { item in
                                StatTile(title: item.title, value: DurationText.short(item.week.batteryTime),
                                         caption: weekCaption(item.week), fill: AnyShapeStyle(ChartSurface.card))
                            }
                            // Hidden weeks keep their slot, so one tile doesn't stretch across the card.
                            ForEach(weeks.count..<usage.weeks.count, id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                emptyState("Use the Mac on battery for a while to see usage.", symbol: "chart.bar")
            }
        }
    }

    /// Days and weeks that ended before this were never recorded, so they're left out
    /// rather than shown as zero.
    private var firstReading: Date { battery.history.first?.timestamp ?? .distantPast }

    private var recordedWeeks: [(title: String, week: UsagePeriod)] {
        let firstReading = self.firstReading
        let cal = Calendar.current
        return usage.weeks.enumerated().compactMap { index, week in
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: week.start) ?? week.start
            // This week always shows, even before the first reading lands.
            guard end > firstReading || index == usage.weeks.count - 1 else { return nil }
            let title = switch usage.weeks.count - 1 - index {
            case 0: "This week"
            case 1: "Last week"
            default: "Week of " + week.start.formatted(.dateTime.month(.abbreviated).day())
            }
            return (title, week)
        }
    }

    private func weekCaption(_ week: UsagePeriod) -> String? {
        guard week.batteryTime > 0 else { return nil }
        var parts = ["\(week.percentUsed)% used"]
        if let watts = week.averageWatts {
            parts.append(watts.formatted(.number.precision(.fractionLength(1))) + " W")
        }
        return parts.joined(separator: " · ")
    }
}

private struct UsageChart: View {
    let days: [UsagePeriod]
    let recordedFrom: Date
    @Bindable var hover: ChartHover

    var body: some View {
        let cal = Calendar.current
        // Today always counts; earlier days only if they end after the first reading.
        let recorded = days.enumerated().filter { index, day in
            index == days.count - 1 || (cal.date(byAdding: .day, value: 1, to: day.start) ?? day.start) > recordedFrom
        }.map(\.element)
        let selected = hover.usageDay.flatMap { date in
            recorded.first { cal.isDate($0.start, inSameDayAs: date) }
        }
        Chart {
            ForEach(recorded, id: \.start) { day in
                BarMark(x: .value("Day", day.start, unit: .day),
                        y: .value("Hours", day.batteryTime / 3600),
                        width: .ratio(0.55))
                    .foregroundStyle(ChartSurface.series.opacity(selected == nil || selected?.start == day.start ? 1 : 0.45))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            }
            if let selected {
                BarMark(x: .value("Day", selected.start, unit: .day),
                        y: .value("Hours", selected.batteryTime / 3600),
                        width: .ratio(0.55))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverReadout(
                            value: DurationText.short(selected.batteryTime),
                            detail: "\(selected.start.formatted(.dateTime.weekday(.wide))) · \(selected.percentUsed)% used")
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...yAxis.max)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxis.ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text(Self.tickLabel(hours)) }
                }
            }
        }
        .chartXSelection(value: $hover.usageDay)
        .accessibilityLabel("Time on battery by day")
    }

    /// Always the full 7 days, so unrecorded days keep their (empty) slot.
    private var xDomain: ClosedRange<Date> {
        let first = days.first?.start ?? .now
        let last = days.last?.start ?? first
        return first...(Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last)
    }

    /// Whole ticks at most 4 steps apart: 15 m steps for a light week, hours for a full one.
    private var yAxis: (max: Double, ticks: [Double]) {
        let top = max((days.map { $0.batteryTime / 3600 }.max() ?? 0) * 1.1, 1)
        let step = [0.25, 0.5, 1, 2, 3, 4, 6].first { top / $0 <= 4 } ?? 6
        let max = (top / step).rounded(.up) * step
        return (max, Array(stride(from: 0, through: max + step / 2, by: step)))
    }

    private static func tickLabel(_ hours: Double) -> String {
        if hours == 0 { return "0" }
        if hours < 1 { return "\(Int((hours * 60).rounded()))m" }
        if hours == hours.rounded() { return "\(Int(hours))h" }
        return hours.formatted(.number.precision(.fractionLength(1))) + "h"
    }
}

// MARK: - Discharge sessions

struct SessionsSection: View {
    static let collapsedCount = 20

    let sessions: [DischargeSession]
    @Bindable var reports: ReportsModel

    var body: some View {
        ChartCard(title: "Discharge sessions", subtitle: "Each discharge of 10% or more, newest first") {
            if sessions.isEmpty {
                emptyState("Sessions appear after a discharge of 10% or more.", symbol: "battery.50percent")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SessionsTable(sessions: reports.showAllSessions
                                  ? sessions : Array(sessions.prefix(Self.collapsedCount)))
                    if sessions.count > Self.collapsedCount {
                        Button(reports.showAllSessions ? "Show newest \(Self.collapsedCount)" : "Show all \(sessions.count)") {
                            reports.showAllSessions.toggle()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
        }
    }
}

private struct SessionsTable: View {
    let sessions: [DischargeSession]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            GridRow {
                SubHeading("Start")
                    .frame(maxWidth: .infinity, alignment: .leading)
                SubHeading("Duration").gridColumnAlignment(.trailing)
                SubHeading("Used").gridColumnAlignment(.trailing)
                SubHeading("Per full charge").gridColumnAlignment(.trailing)
            }
            Divider()
            ForEach(sessions, id: \.start) { session in
                GridRow {
                    Text(session.start.formatted(ReportFormat.sessionStart))
                    Text(DurationText.short(session.end.timeIntervalSince(session.start)))
                    Text("\(session.percentDrop)%")
                    Text(DurationText.short(session.hoursPerFullCharge * 3600))
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Charging habits

struct ChargingSection: View {
    /// A "typical" level from fewer charges than this would be one charge, not a habit.
    static let minChargesForTypical = 3

    let charging: ChargingReport

    var body: some View {
        ChartCard(title: "Charging habits", subtitle: "How you charge, last 28 days") {
            if tiles.isEmpty {
                emptyState("Charging habits appear after a few charges.", symbol: "powerplug")
            } else {
                TileGrid(tiles: tiles, columns: 3, fill: AnyShapeStyle(ChartSurface.card))
            }
        }
    }

    private var tiles: [Tile] {
        var result: [Tile] = []
        if charging.chargeCount >= Self.minChargesForTypical {
            if let p = charging.typicalPlugInPercent {
                result.append(Tile(title: "Plug in at", value: "\(p)%", caption: "typical"))
            }
            if let p = charging.typicalUnplugPercent {
                result.append(Tile(title: "Unplug at", value: "\(p)%", caption: "typical"))
            }
        }
        if let t = charging.averageDailyTimeAtFull, let days = charging.timeAtFullDays {
            result.append(Tile(title: "At 100% on power", value: DurationText.short(t),
                               caption: days == 1 ? "a day, today" : "a day, last \(days) days"))
        }
        if let c = charging.cyclesPerWeek {
            result.append(Tile(title: "Cycles added", value: c.formatted(.number.precision(.fractionLength(1))),
                               caption: "a week"))
        }
        if let w = charging.usualChargerWatts {
            result.append(Tile(title: "Charger", value: "\(w) W", caption: "used most"))
        }
        return result
    }
}

// MARK: - Health trend

struct HealthTrendSection: View {
    let trend: HealthTrend
    /// Built off the main thread with the report; the trend is fitted to these same points.
    let points: [HealthPoint]
    let hover: ChartHover

    var body: some View {
        ChartCard(title: "Health trend", subtitle: "Projected from daily full charge capacity vs. design") {
            if let sentence = HealthTrendCopy.sentence(for: trend, calendar: .current) {
                content(sentence)
            } else if case .notEnoughData(let days) = trend {
                emptyState("Health trend needs two weeks of history (\(days == 1 ? "1 day" : "\(days) days") so far).",
                           symbol: "heart.text.square")
            }
        }
    }

    private func content(_ sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sentence)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            if points.count >= HistoryData.minPoints, let first = points.first, let last = points.last {
                HealthChart(points: points,
                            domain: first.day...max(last.day, first.day.addingTimeInterval(86_400)),
                            hover: hover)
                    .frame(height: 140)
            }
        }
    }
}

// MARK: - Sleep drain

struct SleepSection: View {
    static let periodCount = 7

    /// `nil` when the sleep log couldn't be read.
    let sleep: SleepReport?

    var body: some View {
        ChartCard(title: "Sleep drain", subtitle: "Charge lost while asleep on battery, last 7 days") {
            if let sleep {
                content(sleep)
            } else {
                NotEnoughHistory(title: "Sleep log unavailable",
                                 message: "Couldn't read the sleep log. Reports try again in a few minutes.",
                                 symbol: "moon.zzz", compact: true)
            }
        }
    }

    @ViewBuilder
    private func content(_ sleep: SleepReport) -> some View {
        if sleep.periods.isEmpty {
            emptyState("No sleep on battery in the last 7 days.", symbol: "moon.zzz")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 20) {
                    if let perHour = sleep.percentPerHour {
                        StatTile(title: "Average drain", value: ReportFormat.perHour(perHour),
                                 caption: "while asleep", fill: AnyShapeStyle(ChartSurface.card))
                            .frame(width: 170)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !sleep.wakeReasons.isEmpty {
                        WakeReasons(reasons: sleep.wakeReasons)
                    }
                }
                PeriodsTable(periods: Array(sleep.periods.prefix(Self.periodCount)))
            }
        }
    }
}

private struct WakeReasons: View {
    let reasons: [WakeReasonCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SubHeading("What woke the Mac")
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 3) {
                ForEach(reasons, id: \.reason) { item in
                    GridRow {
                        Text(Self.label(item.reason))
                        Text(item.count.formatted())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    static func label(_ reason: WakeReason) -> String {
        switch reason {
        case .lid: "Lid opened"
        case .userInput: "Keyboard or trackpad"
        case .network: "Network activity"
        case .scheduled: "Scheduled maintenance"
        case .powerButton: "Power button"
        case .other: "Other"
        }
    }
}

private struct PeriodsTable: View {
    let periods: [SleepPeriod]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            GridRow {
                SubHeading("Asleep")
                    .frame(maxWidth: .infinity, alignment: .leading)
                SubHeading("Duration").gridColumnAlignment(.trailing)
                SubHeading("Lost").gridColumnAlignment(.trailing)
            }
            Divider()
            ForEach(periods, id: \.start) { period in
                GridRow {
                    Text((period.start..<period.end).formatted(
                        .interval.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    Text(DurationText.short(period.end.timeIntervalSince(period.start)))
                    Text("\(period.percentLost)%")
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Top battery users

struct AppsSection: View {
    let apps: [AppShare]

    var body: some View {
        ChartCard(title: "Top battery users", subtitle: "Share of energy impact on battery, last 7 days") {
            if apps.isEmpty {
                emptyState("App energy is sampled every 5 minutes on battery.", symbol: "app.badge")
            } else {
                AppBars(apps: apps)
            }
        }
    }
}

/// Ranked horizontal bars. Bars scale to the largest share so the ranking fills the track;
/// the printed percentage carries the exact value.
private struct AppBars: View {
    let apps: [AppShare]

    var body: some View {
        let top = max(apps.map(\.share).max() ?? 1, .ulpOfOne)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(apps, id: \.name) { app in
                GridRow {
                    Text(app.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 150, alignment: .leading)
                    GeometryReader { proxy in
                        UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                            .fill(ChartSurface.series)
                            .frame(width: max(proxy.size.width * app.share / top, 2))
                    }
                    .frame(height: 10)
                    Text(Self.percent(app.share))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(app.name), \(Self.percent(app.share))")
            }
        }
    }

    static func percent(_ share: Double) -> String {
        share < 0.005 ? "<1%" : share.formatted(.percent.precision(.fractionLength(0)))
    }
}
