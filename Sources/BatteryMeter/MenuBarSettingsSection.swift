import SwiftUI
import BatteryCore

extension MenuBarFormat {
    var title: String {
        switch self {
        case .hours: "Hours left"
        case .percent: "Percent"
        case .both: "Hours and percent"
        case .watts: "Power draw"
        case .none: "None"
        }
    }
}

/// The Settings "Menu bar" group: the five choices and a live preview of the item.
struct MenuBarSettingsSection: View {
    let model: BatteryModel
    @AppStorage("menuBarIcon") private var icon: MenuBarIconStyle = MenuBarStyle.standard.icon
    @AppStorage("menuBarFormat") private var format: MenuBarFormat = MenuBarStyle.standard.format
    @AppStorage("menuBarColors") private var colors: MenuBarColorMode = MenuBarStyle.standard.colors
    @AppStorage("menuBarLowThreshold") private var lowThreshold = MenuBarStyle.standard.lowThreshold
    @AppStorage("menuBarTimeStyle") private var timeStyle: MenuBarTimeStyle = MenuBarStyle.standard.timeStyle

    private var style: MenuBarStyle {
        MenuBarStyle(icon: icon, format: format, colors: colors,
                     lowThreshold: MenuBarStyle.lowThresholds.contains(lowThreshold) ? lowThreshold : 10,
                     timeStyle: timeStyle)
    }

    var body: some View {
        Section("Menu bar") {
            LabeledContent("Preview") {
                MenuBarPreview(style: style, source: PreviewSource(model: model))
            }
            Picker("Icon", selection: $icon) {
                ForEach(MenuBarIconStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Text", selection: $format) {
                ForEach(MenuBarFormat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if style.textIncludesHours {
                Picker("Time style", selection: $timeStyle) {
                    ForEach(MenuBarTimeStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Picker("Colors", selection: $colors) {
                ForEach(MenuBarColorMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if colors != .monochrome {
                Picker("Low battery at", selection: $lowThreshold) {
                    ForEach(MenuBarStyle.lowThresholds, id: \.self) { Text("\($0)%").tag($0) }
                }
            }
        }
    }
}

/// What the preview draws: the live reading, or a sample when there is none.
struct PreviewSource {
    let percent: Int
    let state: PowerState
    let watts: Double?

    @MainActor
    init(model: BatteryModel) {
        if let reading = model.reading, let state = model.state {
            percent = reading.percent
            self.state = state
            watts = model.liveWatts
        } else {
            percent = 75
            state = .onBattery(timeLeft: 5.5 * 3600)
            watts = 12.4
        }
    }

    init(percent: Int, state: PowerState, watts: Double?) {
        self.percent = percent
        self.state = state
        self.watts = watts
    }
}

/// The menu bar item on a small strip, built from the same pieces as the real one.
struct MenuBarPreview: View {
    let style: MenuBarStyle
    let source: PreviewSource
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let role = MenuBarAppearance.colorRole(percent: source.percent, state: source.state, style: style)
        let text = MenuBarText.text(
            state: source.state, percent: source.percent, format: style.format,
            timeStyle: style.timeStyle, watts: source.watts)
        HStack(spacing: 4) {
            switch style.effectiveIcon {
            case .symbol:
                Image(systemName: MenuBarAppearance.symbolName(percent: source.percent, state: source.state))
                    .foregroundStyle(role.color ?? .primary)
            case .percentInside:
                Image(nsImage: BatteryIconRenderer.image(
                    percent: source.percent, charging: source.state.isCharging, role: role,
                    ink: scheme == .dark ? .white : .black))
            case .none:
                EmptyView()
            }
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: NSFont.systemFontSize).monospacedDigit())
                    .foregroundStyle(role.color ?? .primary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

extension PowerState {
    var isCharging: Bool {
        if case .charging = self { return true }
        return false
    }
}

extension MenuBarColorRole {
    /// The system color, or nil for the menu bar's own.
    var color: Color? {
        switch self {
        case .none: nil
        case .low: .red
        case .charging: .green
        }
    }
}

private extension MenuBarIconStyle {
    var title: String {
        switch self {
        case .symbol: "Battery symbol"
        case .percentInside: "Battery with percentage inside"
        case .none: "No icon"
        }
    }
}

private extension MenuBarTimeStyle {
    var title: String {
        switch self {
        case .hoursMinutes: "6h 30m"
        case .clock: "6:30"
        }
    }
}

private extension MenuBarColorMode {
    var title: String {
        switch self {
        case .monochrome: "Monochrome"
        case .lowOnly: "Red when low"
        case .lowAndCharging: "Red when low, green when charging"
        }
    }
}
