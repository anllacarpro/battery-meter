import AppKit
import SwiftUI

/// Owns the main window, created on the first `show`. While it's open the app is a
/// regular app (Dock icon, main menu); closing it returns to menu bar only.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private static let autosaveName = "MainWindow"
    private let model: BatteryModel
    private let reports: ReportsModel
    private let hover: ChartHover
    private let settings: SettingsState
    private var window: NSWindow?

    init(model: BatteryModel, reports: ReportsModel, hover: ChartHover, settings: SettingsState) {
        self.model = model
        self.reports = reports
        self.hover = hover
        self.settings = settings
    }

    /// Opens (or brings forward) the window, on `pane` when given; nil keeps the last pane.
    func show(pane: SidebarItem?) {
        if let pane {
            // MainWindow reads this through @AppStorage, so an open window switches too.
            UserDefaults.standard.set(pane.rawValue, forKey: "sidebarSelection")
        }
        let window = self.window ?? makeWindow()
        if window.contentViewController == nil {
            // Rebuilt after each close, like a SwiftUI Window scene: the panes' onAppear
            // runs again and nothing renders while the window is closed.
            let frame = window.frame
            window.contentViewController = hostingController()
            window.setFrame(frame, display: false)
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            // Full-size content so the sidebar runs under the toolbar, as in a SwiftUI Window.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true)
        window.title = "Battery Meter"
        // Matches MainSplitView's `.toolbar(removing: .title)`.
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController()
        window.setContentSize(NSSize(width: 760, height: 520))
        window.contentMinSize = NSSize(width: 640, height: 440)
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        window.delegate = self
        self.window = window
        return window
    }

    private func hostingController() -> NSViewController {
        let hosting = NSHostingController(
            rootView: MainWindow(model: model, reports: reports, hover: hover, settings: settings))
        // The toolbar (sidebar toggle, removed title) comes from SwiftUI; the title stays ours.
        hosting.sceneBridgingOptions = [.toolbars]
        hosting.sizingOptions = [.minSize]
        return hosting
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            // Dropping the content must not resize the window (and its autosaved frame).
            let frame = window.frame
            window.contentViewController = nil
            window.setFrame(frame, display: false)
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
