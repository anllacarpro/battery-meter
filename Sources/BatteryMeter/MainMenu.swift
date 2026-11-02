import AppKit

/// The main menu, visible while the main window makes the app a regular app.
@MainActor
enum MainMenu {
    static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Battery Meter",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: settingsAction, keyEquivalent: ",")
        settings.target = settingsTarget
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Battery Meter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Battery Meter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Battery Meter")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: editMenu, title: "Edit")

        let viewMenu = NSMenu(title: "View")
        let sidebar = viewMenu.addItem(withTitle: "Show Sidebar",
                                       action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.control, .command]
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen",
                                          action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        main.addItem(submenu: viewMenu, title: "View")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
