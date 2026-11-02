import Foundation

public enum QuickMenuAction: Equatable, Sendable {
    case open, reports, history, health, settings
    case setFormat(MenuBarFormat)
    case toggleLaunchAtLogin
    case quit
}

public struct QuickMenuItem: Equatable, Sendable {
    public var title: String
    public var action: QuickMenuAction?
    public var isChecked: Bool
    /// "" when none. "," and "q" are used with the command modifier.
    public var keyEquivalent: String
    public var children: [QuickMenuItem]
    public var isSeparator: Bool

    public init(
        title: String,
        action: QuickMenuAction? = nil,
        isChecked: Bool = false,
        keyEquivalent: String = "",
        children: [QuickMenuItem] = [],
        isSeparator: Bool = false
    ) {
        self.title = title
        self.action = action
        self.isChecked = isChecked
        self.keyEquivalent = keyEquivalent
        self.children = children
        self.isSeparator = isSeparator
    }

    static let separator = QuickMenuItem(title: "", isSeparator: true)
}

/// The right-click quick menu as plain data.
public enum QuickMenu {
    public static func items(format: MenuBarFormat, launchAtLogin: Bool) -> [QuickMenuItem] {
        let formats: [(MenuBarFormat, String)] = [
            (.hours, "Hours left"),
            (.percent, "Percent"),
            (.both, "Hours and percent"),
        ]
        return [
            QuickMenuItem(title: "Open Battery Meter", action: .open),
            QuickMenuItem(title: "Reports…", action: .reports),
            QuickMenuItem(title: "History…", action: .history),
            QuickMenuItem(title: "Health…", action: .health),
            .separator,
            QuickMenuItem(
                title: "Menu bar shows",
                children: formats.map {
                    QuickMenuItem(title: $0.1, action: .setFormat($0.0), isChecked: $0.0 == format)
                }
            ),
            QuickMenuItem(title: "Launch at login", action: .toggleLaunchAtLogin, isChecked: launchAtLogin),
            QuickMenuItem(title: "Settings…", action: .settings, keyEquivalent: ","),
            .separator,
            QuickMenuItem(title: "Quit Battery Meter", action: .quit, keyEquivalent: "q"),
        ]
    }
}
