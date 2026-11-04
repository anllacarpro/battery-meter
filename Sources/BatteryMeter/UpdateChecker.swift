import Foundation
import Observation
import BatteryCore

/// Asks GitHub whether a newer release than the running version exists. It never installs
/// anything: Homebrew (`brew upgrade --cask battery-meter`) or the release page does that.
/// Owned by `SettingsState`, so the Settings pane, the quick menu and the launch check
/// share one result.
@MainActor @Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(LatestRelease)
        case failed(String)
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/anllacarpro/battery-meter/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let interval: TimeInterval = 24 * 60 * 60

    private(set) var state = State.idle

    /// nil for a build that isn't a bundled release (`swift run`).
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    var availableRelease: LatestRelease? {
        if case .available(let release) = state { release } else { nil }
    }

    /// The automatic check: only the installed app, at most once a day, silent on failure.
    func checkIfDue() {
        let defaults = UserDefaults.standard
        guard InstallLocation.isInstalled(Bundle.main.bundleURL),
              Date().timeIntervalSince(defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast) >= Self.interval
        else { return }
        Task { await check() }
    }

    func check() async {
        guard let currentVersion, state != .checking else { return }
        state = .checking
        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(LatestRelease.self, from: data)
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            state = release.isNewer(than: currentVersion) ? .available(release) : .upToDate
        } catch {
            state = .failed("Couldn't check for updates.")
        }
    }
}
