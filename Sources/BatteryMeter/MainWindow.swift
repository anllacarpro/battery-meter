import SwiftUI
import Observation

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, reports, history, health, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .reports: "Reports"
        case .history: "History"
        case .health: "Health"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .reports: "chart.bar.doc.horizontal"
        case .history: "chart.xyaxis.line"
        case .health: "heart.text.square"
        case .settings: "gearshape"
        }
    }
}

/// Pointer-hover selections for the History charts. Owned by the App (no `@State` under
/// Command Line Tools) and kept apart from `BatteryModel` so hovering never touches it.
@MainActor @Observable
final class ChartHover {
    var sessionDate: Date?
    var healthDate: Date?
    var usageDay: Date?
}

/// The window's root: persists the sidebar selection.
struct MainWindow: View {
    let model: BatteryModel
    let reports: ReportsModel
    let hover: ChartHover
    let settings: SettingsState
    @AppStorage("sidebarSelection") private var selection: SidebarItem = .overview

    var body: some View {
        MainSplitView(model: model, reports: reports, hover: hover, settings: settings, selection: $selection)
    }
}

struct MainSplitView: View {
    let model: BatteryModel
    let reports: ReportsModel
    let hover: ChartHover
    let settings: SettingsState
    @Binding var selection: SidebarItem

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(removing: .title)
        .frame(minWidth: 640, minHeight: 440)
    }

    /// List selection is optional; an empty click keeps the current pane.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(get: { selection }, set: { if let item = $0 { selection = item } })
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .overview: OverviewView(model: model, reports: reports)
        case .reports: ReportsView(reports: reports, battery: model, hover: hover)
        case .history: HistoryView(history: model.history, hover: hover)
        case .health: HealthView(reading: model.reading)
        case .settings: SettingsView(model: model, settings: settings)
        }
    }
}

/// Large in-content title, as in System Settings panes.
struct PaneTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title.bold())
            .accessibilityAddTraits(.isHeader)
    }
}
