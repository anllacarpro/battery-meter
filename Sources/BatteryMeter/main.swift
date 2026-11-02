import AppKit

// AppKit entry point. Top-level code runs on the main thread, so the main actor can be
// assumed for setup; `run()` never returns until the app terminates.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate  // weak: kept alive by this scope for the app's lifetime
    withExtendedLifetime(delegate) {
        app.run()
    }
}
