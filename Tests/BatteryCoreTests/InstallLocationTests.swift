import Foundation
import Testing
@testable import BatteryCore

@Suite struct InstallLocationTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    @Test func applicationsFoldersCount() {
        #expect(InstallLocation.isInstalled(URL(fileURLWithPath: "/Applications/Battery Meter.app"), home: home))
        #expect(InstallLocation.isInstalled(
            URL(fileURLWithPath: "/Users/someone/Applications/Battery Meter.app"), home: home))
    }

    @Test func buildsAndUnbundledRunsDoNot() {
        for path in [
            "/Users/someone/Documents/battery_meter/build/Battery Meter.app",
            "/Users/someone/Documents/battery_meter/.build/debug",
            "/Applications",
            "/ApplicationsOld/Battery Meter.app",
            "/Users/other/Applications/Battery Meter.app",
        ] {
            #expect(!InstallLocation.isInstalled(URL(fileURLWithPath: path), home: home), "\(path)")
        }
    }

    @Test func resolvesSymlinks() throws {
        let fm = FileManager.default
        // The temporary directory itself sits behind the /var -> /private/var symlink.
        let root = fm.temporaryDirectory.appendingPathComponent("InstallLocationTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let fakeHome = root.appendingPathComponent("home")
        let installed = fakeHome.appendingPathComponent("Applications/Battery Meter.app")
        try fm.createDirectory(at: installed, withIntermediateDirectories: true)
        let build = root.appendingPathComponent("project/build/Battery Meter.app")
        try fm.createDirectory(at: build, withIntermediateDirectories: true)

        // A link into ~/Applications counts; a link in ~/Applications pointing at build/ doesn't.
        let linkToInstalled = root.appendingPathComponent("Shortcut.app")
        try fm.createSymbolicLink(at: linkToInstalled, withDestinationURL: installed)
        let linkToBuild = fakeHome.appendingPathComponent("Applications/Linked.app")
        try fm.createSymbolicLink(at: linkToBuild, withDestinationURL: build)

        #expect(InstallLocation.isInstalled(installed, home: fakeHome))
        #expect(InstallLocation.isInstalled(linkToInstalled, home: fakeHome))
        #expect(!InstallLocation.isInstalled(linkToBuild, home: fakeHome))
    }
}
