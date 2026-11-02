import AppKit
import SwiftUI
import BatteryCore

/// The menu bar item: a left click toggles the popover, a right click (or Control-click)
/// opens the quick menu. Lives as long as the app.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    /// A transient popover closes on mouse-down on the button (it counts as outside), so
    /// the same click's mouse-up must not reopen it.
    private static let reopenGuard: TimeInterval = 0.25
    private let model: BatteryModel
    private let settings: SettingsState
    private let window: MainWindowController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var defaultsObserver: NSObjectProtocol?
    private var shownFormat: MenuBarFormat?
    /// Monotonic time of the last popover close.
    private var lastPopoverClose: TimeInterval = 0

    init(model: BatteryModel, sampler: EnergySampler, settings: SettingsState, window: MainWindowController) {
        self.model = model
        self.settings = settings
        self.window = window
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let actions = PopoverActions(
            openWindow: { [weak self] in self?.showWindow(pane: nil) },
            openReports: { [weak self] in self?.showWindow(pane: .reports) },
            openSettings: { [weak self] in self?.showWindow(pane: .settings) },
            quit: { NSApp.terminate(nil) })
        let hosting = NSHostingController(rootView: PopoverView(model: model, sampler: sampler, actions: actions))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        model.onRefresh = { [weak self] in self?.updateLabel() }
        // Any defaults write posts this; only a menuBarFormat change redraws.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.shownFormat != Self.currentFormat else { return }
                self.updateLabel()
            }
        }
        updateLabel()
    }

    isolated deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private static var currentFormat: MenuBarFormat {
        UserDefaults.standard.string(forKey: "menuBarFormat").flatMap(MenuBarFormat.init(rawValue:)) ?? .hours
    }

    func updateLabel() {
        let format = Self.currentFormat
        shownFormat = format
        guard let button = statusItem.button else { return }
        guard let reading = model.reading, let state = model.state else {
            button.image = symbol("battery.0percent")
            button.title = ""
            button.contentTintColor = nil
            button.setAccessibilityLabel("Battery Meter, no battery reading")
            return
        }
        let percent = reading.percent
        button.image = symbol(MenuBarAppearance.symbolName(percent: percent, state: state))
        button.title = MenuBarText.text(state: state, percent: percent, format: format)
        button.contentTintColor = MenuBarAppearance.isLow(percent: percent, state: state) ? .systemRed : nil
        button.setAccessibilityLabel(MenuBarAppearance.accessibilityLabel(percent: percent, state: state))
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    // MARK: Clicks

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if ProcessInfo.processInfo.systemUptime - lastPopoverClose < Self.reopenGuard {
            return  // this click already closed it
        } else if let button = statusItem.button {
            // A transient popover only closes on an outside click while the app is active
            // and its window is key. Activating an accessory app adds no Dock icon.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            button.highlight(true)
        }
    }

    /// Closes at once (before the menu or the window opens) and un-highlights directly,
    /// not relying on `close()` reaching the delegate.
    private func closePopover() {
        if popover.isShown { popover.close() }
        statusItem.button?.highlight(false)
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverClose = ProcessInfo.processInfo.systemUptime
        statusItem.button?.highlight(false)
    }

    private func showMenu() {
        closePopover()
        settings.refreshLaunchAtLogin()  // it can change in System Settings
        let menu = NSMenu()
        menu.delegate = self
        for item in QuickMenu.items(format: Self.currentFormat, launchAtLogin: settings.launchAtLogin) {
            menu.addItem(menuItem(item))
        }
        // Set only while it's open: with a menu attached, every click would open it.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // performClick returns once tracking ends; the chosen item's action still runs
        // (it's dispatched through representedObject). menuDidClose clears it too.
        statusItem.menu = nil
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    private func menuItem(_ item: QuickMenuItem) -> NSMenuItem {
        if item.isSeparator { return .separator() }
        let result = NSMenuItem(
            title: item.title,
            action: item.action == nil ? nil : #selector(menuItemChosen(_:)),
            keyEquivalent: item.keyEquivalent)
        result.keyEquivalentModifierMask = item.keyEquivalent.isEmpty ? [] : .command
        result.target = self
        result.representedObject = item.action
        result.state = item.isChecked ? .on : .off
        if !item.children.isEmpty {
            let submenu = NSMenu(title: item.title)
            for child in item.children { submenu.addItem(menuItem(child)) }
            result.submenu = submenu
        }
        return result
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? QuickMenuAction else { return }
        switch action {
        case .open: showWindow(pane: .overview)
        case .reports: showWindow(pane: .reports)
        case .history: showWindow(pane: .history)
        case .health: showWindow(pane: .health)
        case .settings: showWindow(pane: .settings)
        case .setFormat(let format):
            UserDefaults.standard.set(format.rawValue, forKey: "menuBarFormat")
        case .toggleLaunchAtLogin:
            // A failure shows under the Settings pane's toggle, as when toggled there.
            if !settings.toggleLaunchAtLogin() { showWindow(pane: .settings) }
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func showWindow(pane: SidebarItem?) {
        closePopover()
        window.show(pane: pane)
    }
}
