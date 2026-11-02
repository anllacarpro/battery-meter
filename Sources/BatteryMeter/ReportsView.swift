import SwiftUI
import BatteryCore

/// The Reports pane: six sections rendered from `ReportsModel.report`, which is built off
/// the main thread. Until the first report lands it shows one calm loading state.
struct ReportsView: View {
    let reports: ReportsModel
    let battery: BatteryModel
    let hover: ChartHover

    var body: some View {
        Group {
            if let report = reports.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PaneTitle("Reports")
                        UsageSection(usage: report.usage, battery: battery, hover: hover)
                        SessionsSection(sessions: report.sessions, reports: reports)
                        ChargingSection(charging: report.charging)
                        HealthTrendSection(trend: report.health, battery: battery, hover: hover)
                        SleepSection(sleep: report.sleep)
                        AppsSection(apps: report.apps)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    PaneTitle("Reports")
                    BuildingReports()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .onAppear { reports.refresh() }
    }
}

private struct BuildingReports: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Building reports…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
