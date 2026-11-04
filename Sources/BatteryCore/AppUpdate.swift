import Foundation

/// A dotted numeric version such as `0.1.3`; a leading `v` (as in git tags) is ignored.
public struct AppVersion: Comparable, Sendable {
    private let parts: [Int]

    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let numbers = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        // Trailing zeros don't change the version, so `1.0` equals `1.0.0`.
        var parts = numbers.compactMap { $0 }
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<count {
            let (a, b) = (i < lhs.parts.count ? lhs.parts[i] : 0, i < rhs.parts.count ? rhs.parts[i] : 0)
            if a != b { return a < b }
        }
        return false
    }
}

/// The part of GitHub's "latest release" response the update check needs.
public struct LatestRelease: Decodable, Equatable, Sendable {
    public let tag: String
    public let url: URL

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name", url = "html_url"
    }

    /// The tag without its `v`, for display.
    public var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }

    /// True when this release is newer than `current`. An unreadable version on either
    /// side is never an update.
    public func isNewer(than current: String) -> Bool {
        guard let latest = AppVersion(tag), let installed = AppVersion(current) else { return false }
        return latest > installed
    }
}
