import SwiftUI
import Charts
import BatteryCore

struct HistoryView: View {
    let history: [BatteryReading]
    let hover: ChartHover

    var body: some View {
        // Derived here, not in the chart views, so pointer hover never recomputes it.
        let data = HistoryData(history: history)
        // Charts share the pane's height (below the toolbar); under the minimum it scrolls.
        GeometryReader { proxy in
            ScrollView {
                content(data)
                    .frame(height: max(proxy.size.height, Self.minHeight))
            }
        }
    }

    /// Fits both cards with `ChartCard.minChartHeight` plots.
    private static let minHeight: CGFloat = 450

    private func content(_ data: HistoryData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneTitle("History")
            ChartCard(
                title: "Hours per full charge",
                subtitle: data.sessions.count >= HistoryData.minPoints
                    ? "\(data.sessions.count) discharge sessions, each scaled to 100%"
                    : "Each discharge session, scaled to 100%"
            ) {
                if data.sessions.count >= HistoryData.minPoints {
                    SessionsChart(sessions: data.sessions, domain: data.domain, hover: hover)
                } else {
                    NotEnoughHistory()
                }
            }
            ChartCard(
                title: "Battery health",
                subtitle: "Daily average of full charge capacity vs. design"
            ) {
                if data.health.count >= HistoryData.minPoints {
                    HealthChart(points: data.health, domain: data.domain, hover: hover)
                } else {
                    NotEnoughHistory()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

// MARK: - Data

struct HistoryData {
    /// A line needs two points; one point alone reads as a broken chart.
    static let minPoints = 2

    let sessions: [DischargeSession]
    let health: [HealthPoint]
    /// Shared x-axis span so the two charts line up.
    let domain: ClosedRange<Date>

    init(history: [BatteryReading]) {
        sessions = FullChargeLearner.sessions(in: history)
        health = DailyHealth.points(in: history)
        let dates = sessions.map(\.start) + health.map(\.day)
        let lo = dates.min() ?? .now
        let hi = max(dates.max() ?? .now, lo.addingTimeInterval(86_400))
        domain = lo...hi
    }
}

// MARK: - Cards

/// Chart colors, all explicit: hierarchical styles resolve unpredictably inside Charts.
/// Cards use the same fill as grouped Form sections; system blue passes the dataviz
/// checks (lightness, chroma, 3:1 contrast) on it in light and dark.
enum ChartSurface {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .quaternarySystemFill)
    static let series = Color.blue
    static let rule = Color(nsColor: .tertiaryLabelColor)
}

private struct ChartCard<Content: View>: View {
    static var minChartHeight: CGFloat { 90 }

    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, minHeight: Self.minChartHeight, maxHeight: .infinity)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .groupBoxStyle(CardGroupBoxStyle())
    }
}

/// Opaque card (as in the mockup) so chart marks and their rings sit on a known surface.
private struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
            configuration.content
        }
        .padding(14)
        .background(ChartSurface.card, in: .rect(cornerRadius: 12))
    }
}

private struct NotEnoughHistory: View {
    var body: some View {
        ContentUnavailableView {
            Label("Not enough history yet", systemImage: "chart.xyaxis.line")
        } description: {
            Text("Charts fill in as Battery Meter records in the background.")
                .font(.subheadline)
        }
    }
}

// MARK: - Charts

private let lineStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

/// 8 pt series dot. `ringed` adds a 2 pt ring in the card color so sparse points stay
/// legible where they cross the line. Dense lines (daily points a few pt apart) go without:
/// the 12 pt ring would paint over the neighbouring segments and detach the dot.
private struct SeriesDot: View {
    var ringed = true

    var body: some View {
        Circle()
            .fill(ChartSurface.series)
            .frame(width: 8, height: 8)
            .padding(ringed ? 2 : 0)
            // The card fill is translucent, so lay it over the window color to get an opaque ring.
            .background {
                if ringed {
                    Circle().fill(ChartSurface.card).background(Circle().fill(ChartSurface.window))
                }
            }
    }
}

private struct SessionsChart: View {
    let sessions: [DischargeSession]
    let domain: ClosedRange<Date>
    @Bindable var hover: ChartHover

    var body: some View {
        let selected = hover.sessionDate.flatMap(nearest)
        Chart {
            ForEach(sessions, id: \.start) { session in
                LineMark(x: .value("Date", session.start), y: .value("Hours", session.hoursPerFullCharge))
                    .lineStyle(lineStyle)
                    .foregroundStyle(ChartSurface.series)
                PointMark(x: .value("Date", session.start), y: .value("Hours", session.hoursPerFullCharge))
                    .symbol { SeriesDot() }
            }
            if let selected {
                RuleMark(x: .value("Date", selected.start))
                    .foregroundStyle(ChartSurface.rule)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverReadout(
                            value: DurationText.short(selected.hoursPerFullCharge * 3600),
                            detail: "\(selected.start.formatted(.dateTime.month(.abbreviated).day())) · \(selected.percentDrop)% used")
                    }
            } else if let last = sessions.last {
                PointMark(x: .value("Date", last.start), y: .value("Hours", last.hoursPerFullCharge))
                    .symbolSize(0)
                    .annotation(position: .top, alignment: .trailing, spacing: 8) {
                        EndLabel(text: DurationText.short(last.hoursPerFullCharge * 3600))
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...yMax)
        .chartXAxis { dateAxis() }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(Int(hours))h") }
                }
            }
        }
        .chartXSelection(value: $hover.sessionDate)
        .accessibilityLabel("Hours per full charge by discharge session")
    }

    /// Headroom above the highest session for the end label.
    private var yMax: Double {
        let top = sessions.map(\.hoursPerFullCharge).max() ?? 1
        return (top * 1.25).rounded(.up)
    }

    private func nearest(to date: Date) -> DischargeSession? {
        sessions.min { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }
}

private struct HealthChart: View {
    let points: [HealthPoint]
    let domain: ClosedRange<Date>
    @Bindable var hover: ChartHover

    var body: some View {
        let selected = hover.healthDate.flatMap(nearest)
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Day", point.day), y: .value("Health", point.percent))
                    .lineStyle(lineStyle)
                    .foregroundStyle(ChartSurface.series)
            }
            if let selected {
                RuleMark(x: .value("Day", selected.day))
                    .foregroundStyle(ChartSurface.rule)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverReadout(
                            value: BatteryFormat.percent(selected.percent),
                            detail: selected.day.formatted(.dateTime.month(.abbreviated).day()))
                    }
                PointMark(x: .value("Day", selected.day), y: .value("Health", selected.percent))
                    .symbol { SeriesDot(ringed: false) }
            } else if let last = points.last {
                PointMark(x: .value("Day", last.day), y: .value("Health", last.percent))
                    .symbol { SeriesDot(ringed: false) }
                    .annotation(position: .top, alignment: .trailing, spacing: 6) {
                        EndLabel(text: BatteryFormat.percent(last.percent))
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: yAxis.domain)
        .chartXAxis { dateAxis() }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxis.ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text(percent.formatted(.number.precision(.fractionLength(0))) + "%")
                    }
                }
            }
        }
        .chartXSelection(value: $hover.healthDate)
        .accessibilityLabel("Battery health by day")
    }

    /// At least 95–100%, so recalibration noise of a few tenths reads as flat rather than
    /// as a cliff; widens (and coarsens the ticks) only when the data needs it.
    private var yAxis: (domain: ClosedRange<Double>, ticks: [Double]) {
        let values = points.map(\.percent)
        let span = (lo: min((values.min() ?? 100).rounded(.down), 95),
                    hi: max(100, (values.max() ?? 100).rounded(.up)))
        let step = [1.0, 2, 5, 10, 25].first { (span.hi - span.lo) / $0 <= 5 } ?? 25
        let first = (span.lo / step).rounded(.down) * step
        let last = (span.hi / step).rounded(.up) * step
        return (first...last, Array(stride(from: first, through: last + step / 2, by: step)))
    }

    private func nearest(to date: Date) -> HealthPoint? {
        points.min { abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date)) }
    }
}

private func dateAxis() -> some AxisContent {
    // No vertical gridlines: the horizontal ones carry the values, the dates only need labels.
    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
        AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1))
        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
    }
}

private struct EndLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
    }
}

private struct HoverReadout: View {
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(ChartSurface.window, in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }
}
