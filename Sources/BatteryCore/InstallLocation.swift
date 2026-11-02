import Foundation

public enum InstallLocation {
    /// True when `bundleURL` is an app bundle inside `/Applications` or `~/Applications`,
    /// after resolving symlinks. Builds run from `build/` or unbundled binaries are not.
    public static func isInstalled(
        _ bundleURL: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        guard bundleURL.pathExtension == "app" else { return false }
        let path = resolved(bundleURL)
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                     home.appendingPathComponent("Applications", isDirectory: true)]
        return roots.contains { path.hasPrefix(resolved($0) + "/") }
    }

    private static func resolved(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
