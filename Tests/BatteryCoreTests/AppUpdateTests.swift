import Foundation
import Testing
@testable import BatteryCore

@Suite struct AppUpdateTests {
    private func release(_ tag: String) -> LatestRelease {
        LatestRelease(tag: tag, url: URL(string: "https://example.com/r")!)
    }

    @Test func versionsCompareNumerically() {
        #expect(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
        #expect(AppVersion("0.2.0")! > AppVersion("0.1.99")!)
        #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
        #expect(!(AppVersion("0.1.3")! < AppVersion("0.1.3")!))
    }

    @Test func leadingVIsIgnored() {
        #expect(AppVersion("v0.1.3") == AppVersion("0.1.3"))
    }

    @Test(arguments: ["", "v", "1..2", "1.x", "1.2.3-beta", "-1.0"])
    func malformedVersionsAreRejected(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func newerReleaseIsAnUpdate() {
        #expect(release("v0.1.4").isNewer(than: "0.1.3"))
        #expect(!release("v0.1.3").isNewer(than: "0.1.3"))
        #expect(!release("v0.1.2").isNewer(than: "0.1.3"))
    }

    @Test func unreadableVersionsAreNeverAnUpdate() {
        #expect(!release("nightly").isNewer(than: "0.1.3"))
        #expect(!release("v0.1.4").isNewer(than: "dev"))
    }

    @Test func decodesGitHubLatestRelease() throws {
        let json = #"{"tag_name":"v0.1.4","html_url":"https://github.com/o/r/releases/tag/v0.1.4","name":"x"}"#
        let decoded = try JSONDecoder().decode(LatestRelease.self, from: Data(json.utf8))
        #expect(decoded.tag == "v0.1.4")
        #expect(decoded.version == "0.1.4")
        #expect(decoded.url.absoluteString == "https://github.com/o/r/releases/tag/v0.1.4")
    }
}
