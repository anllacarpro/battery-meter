import SwiftUI
import Observation
import ServiceManagement
import BatteryCore

/// Settings-pane state that can't live in `@State` under Command Line Tools: the reset
/// confirmation and the launch-at-login status. Owned by the app delegate.
@MainActor @Observable
final class SettingsState {
    static let retentionOptions = [30, 90, 180, 365]

    var confirmingReset = false
    private(set) var launchAtLogin = false
    private var needsApproval = false
    /// The last register/unregister failure, cleared by the next success.
    private var launchAtLoginError: String?

    /// Secondary text under the toggle.
    var launchAtLoginNote: String? {
        launchAtLoginError
            ?? (needsApproval ? "Allow Battery Meter in System Settings > General > Login Items." : nil)
    }

    init() {
        refreshLaunchAtLogin()
    }

    /// On first launch of the installed app, turn launch at login on once so it's the
    /// default; afterwards the user's choice (here or in System Settings) is left alone.
    /// Runs from `build/` or unbundled binaries don't use up the offer, and a failed
    /// registration is shown under the toggle and retried at the next launch.
    func offerLaunchAtLoginOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didOfferLaunchAtLogin"),
              InstallLocation.isInstalled(Bundle.main.bundleURL) else { return }
        let status = SMAppService.mainApp.status
        if status == .enabled || status == .requiresApproval {
            defaults.set(true, forKey: "didOfferLaunchAtLogin")
        } else {
            do {
                try SMAppService.mainApp.register()
                defaults.set(true, forKey: "didOfferLaunchAtLogin")
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
            }
        }
        refreshLaunchAtLogin()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    /// Flips launch at login from outside the Settings pane (the quick menu). Returns false
    /// when it failed; the error then shows under the pane's toggle.
    @discardableResult
    func toggleLaunchAtLogin() -> Bool {
        refreshLaunchAtLogin()
        setLaunchAtLogin(!launchAtLogin)
        return launchAtLoginError == nil
    }

    /// Re-reads the status, which can also change in System Settings.
    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    #if DEBUG
    /// Snapshot-only: shows a note without touching the login item.
    func showSampleError(_ message: String) {
        launchAtLoginError = message
    }
    #endif
}

struct SettingsView: View {
    let model: BatteryModel
    @Bindable var settings: SettingsState
    @AppStorage("menuBarFormat") private var menuBarFormat: MenuBarFormat = .hours
    @AppStorage("retentionDays") private var retentionDays = BatteryModel.defaultRetentionDays

    var body: some View {
        Form {
            Section {
                Toggle(isOn: launchAtLogin) {
                    Text("Launch at login")
                    if let note = settings.launchAtLoginNote {
                        Text(note)
                    }
                }
                Picker("Menu bar shows", selection: $menuBarFormat) {
                    ForEach(MenuBarFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
            } header: {
                // Same alignment as the Health pane's title.
                PaneTitle("Settings")
                    .foregroundStyle(.primary)
                    .padding(.leading, -10)
                    .padding(.bottom, 8)
            }
            Section("History") {
                Picker("Keep history for", selection: retention) {
                    ForEach(SettingsState.retentionOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                LabeledContent {
                    Button("Reset learned data…", role: .destructive) {
                        settings.confirmingReset = true
                    }
                } label: {
                    Text("Learned data")
                    Text("Battery history and hours per full charge")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { settings.refreshLaunchAtLogin() }
        .confirmationDialog("Reset learned data?", isPresented: $settings.confirmingReset) {
            Button("Reset", role: .destructive) { model.resetLearnedData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your battery history and the learned hours per full charge. Your battery isn't affected.")
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) })
    }

    private var retention: Binding<Int> {
        Binding(get: { retentionDays }, set: { days in
            guard days != retentionDays else { return }
            retentionDays = days
            model.applyRetention(days: days)
        })
    }
}

private extension MenuBarFormat {
    var title: String {
        switch self {
        case .hours: "Hours left"
        case .percent: "Percent"
        case .both: "Hours and percent"
        }
    }
}
