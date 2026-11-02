import Foundation

public enum MenuBarIconStyle: String, CaseIterable, Sendable { case symbol, percentInside, none }
public enum MenuBarColorMode: String, CaseIterable, Sendable { case monochrome, lowOnly, lowAndCharging }
/// "6h 30m" or "6:30".
public enum MenuBarTimeStyle: String, CaseIterable, Sendable { case hoursMinutes, clock }
public enum MenuBarColorRole: Sendable { case none, low, charging }

/// How the menu bar item looks, read from `UserDefaults`.
public struct MenuBarStyle: Equatable, Sendable {
    public static let lowThresholds = [5, 10, 15, 20]

    public var icon: MenuBarIconStyle
    public var format: MenuBarFormat
    public var colors: MenuBarColorMode
    /// Percent; one of `lowThresholds`.
    public var lowThreshold: Int
    public var timeStyle: MenuBarTimeStyle

    public static let standard = MenuBarStyle(
        icon: .symbol, format: .hours, colors: .lowOnly, lowThreshold: 10, timeStyle: .hoursMinutes)

    public init(icon: MenuBarIconStyle, format: MenuBarFormat, colors: MenuBarColorMode,
                lowThreshold: Int, timeStyle: MenuBarTimeStyle) {
        self.icon = icon
        self.format = format
        self.colors = colors
        self.lowThreshold = lowThreshold
        self.timeStyle = timeStyle
    }

    /// Anything missing or invalid falls back to the standard value.
    public init(defaults: UserDefaults) {
        let s = MenuBarStyle.standard
        icon = defaults.string(forKey: "menuBarIcon").flatMap(MenuBarIconStyle.init(rawValue:)) ?? s.icon
        format = defaults.string(forKey: "menuBarFormat").flatMap(MenuBarFormat.init(rawValue:)) ?? s.format
        colors = defaults.string(forKey: "menuBarColors").flatMap(MenuBarColorMode.init(rawValue:)) ?? s.colors
        let threshold = defaults.object(forKey: "menuBarLowThreshold") as? Int
        lowThreshold = threshold.flatMap { MenuBarStyle.lowThresholds.contains($0) ? $0 : nil } ?? s.lowThreshold
        timeStyle = defaults.string(forKey: "menuBarTimeStyle").flatMap(MenuBarTimeStyle.init(rawValue:)) ?? s.timeStyle
    }

    /// The icon actually drawn: with no icon and no text the item would be empty, so the
    /// symbol is used.
    public var effectiveIcon: MenuBarIconStyle {
        icon == .none && format == .none ? .symbol : icon
    }

    /// Whether the text can show hours, so the time style matters.
    public var textIncludesHours: Bool { format == .hours || format == .both }
}
