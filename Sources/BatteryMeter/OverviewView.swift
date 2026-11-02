import SwiftUI
import BatteryCore

struct OverviewView: View {
    let model: BatteryModel
    let reports: ReportsModel

    var body: some View {
        Group {
            if let reading = model.reading, let state = model.state {
                ScrollView {
                    OverviewContent(
                        reading: reading, state: state, runtime: model.runtime, fullCharge: model.fullCharge,
                        liveWatts: model.liveWatts, liveVolts: model.liveVolts, liveAmps: model.liveAmps,
                        reports: reports)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                }
            } else {
                EmptyStateView()
                    .frame(maxHeight: .infinity)
            }
        }
        .onAppear { reports.refresh() }
    }
}

private struct OverviewContent: View {
    let reading: BatteryReading
    let state: PowerState
    let runtime: RuntimeEstimate?
    let fullCharge: FullChargeEstimate?
    let liveWatts: Double?
    let liveVolts: Double?
    let liveAmps: Double?
    let reports: ReportsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Overview")
            // The same headline as the popover, so both read alike.
            RuntimeHeadline(reading: reading, state: state, runtime: runtime)
                .padding(.top, 16)
            TileSection(title: "Battery", tiles: [
                BatteryTiles.fullCharge(fullCharge),
                BatteryTiles.health(reading),
                BatteryTiles.cycles(reading),
            ].compactMap { $0 })
            .padding(.top, 24)
            let live = [
                BatteryTiles.power(state: state, watts: liveWatts),
                BatteryTiles.voltage(liveVolts),
                BatteryTiles.amperage(liveAmps),
            ].compactMap { $0 }
            if !live.isEmpty {
                TileSection(title: "Right now", tiles: live)
                    .padding(.top, 20)
            }
            ThisWeekSection(reports: reports)
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TileSection<Accessory: View>: View {
    let title: String
    let tiles: [Tile]
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                accessory
            }
            HStack(spacing: 8) {
                ForEach(tiles) { tile in
                    StatTile(title: tile.title, value: tile.value, caption: tile.caption)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension TileSection where Accessory == EmptyView {
    init(title: String, tiles: [Tile]) {
        self.init(title: title, tiles: tiles) { EmptyView() }
    }
}

/// This week's battery time, charge used and sleep drain from the latest report. Reads
/// `ReportsModel` itself, so a new report redraws only this section. Values the report
/// can't support are hidden; with none left, a single line says so.
private struct ThisWeekSection: View {
    let reports: ReportsModel
    @AppStorage("sidebarSelection") private var selection: SidebarItem = .overview

    var body: some View {
        if let report = reports.report {
            let tiles = Self.tiles(report)
            if tiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    Text("No time on battery yet this week.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                TileSection(title: "This week", tiles: tiles) { seeReports }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("This week")
                .font(.headline)
            Spacer()
            seeReports
        }
    }

    private var seeReports: some View {
        Button("See reports…") { selection = .reports }
            .buttonStyle(.link)
    }

    static func tiles(_ report: BatteryReport) -> [Tile] {
        var result: [Tile] = []
        if let week = report.usage.weeks.last, week.batteryTime > 0 {
            result.append(Tile(title: "Battery time", value: DurationText.short(week.batteryTime)))
            result.append(Tile(title: "Charge used", value: "\(week.percentUsed)%"))
        }
        // Hidden, not zero, when the sleep log couldn't be read.
        if let perHour = report.sleep?.percentPerHour {
            // A rolling window, unlike the calendar-week tiles beside it.
            result.append(Tile(title: "Sleep drain", value: ReportFormat.perHour(perHour), caption: "last 7 days"))
        }
        return result
    }
}
