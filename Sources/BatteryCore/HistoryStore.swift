import Foundation

/// Append-only JSON Lines store of `BatteryReading`s (one per line, ISO 8601 dates).
/// All file access is serialized on a private queue.
public final class HistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "BatteryCore.HistoryStore")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatteryMeter", isDirectory: true)
            .appendingPathComponent("history.jsonl")
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func append(_ r: BatteryReading) throws {
        var line = try Self.makeEncoder().encode(r)
        line.append(0x0A)
        try queue.sync {
            let fm = FileManager.default
            try fm.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: fileURL.path) {
                guard fm.createFile(atPath: fileURL.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let handle = try FileHandle(forUpdating: fileURL)
            defer { try? handle.close() }
            let end = try handle.seekToEnd()
            if end > 0 {
                // A crash mid-write can leave an unterminated last line; start a fresh one.
                try handle.seek(toOffset: end - 1)
                if try handle.read(upToCount: 1) != Data([0x0A]) {
                    line.insert(0x0A, at: 0)
                }
                try handle.seekToEnd()
            }
            try handle.write(contentsOf: line)
        }
    }

    public func load(since: Date) -> [BatteryReading] {
        queue.sync { readAll().filter { $0.timestamp >= since } }
    }

    public func prune(olderThan: Date) throws {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let encoder = Self.makeEncoder()
            var out = Data()
            for r in readAll() where r.timestamp >= olderThan {
                out.append(try encoder.encode(r))
                out.append(0x0A)
            }
            try out.write(to: fileURL, options: .atomic)
        }
    }

    public func reset() throws {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Must be called on `queue`. Undecodable lines (e.g. a truncated tail) are skipped.
    private func readAll() -> [BatteryReading] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = Self.makeDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(BatteryReading.self, from: Data($0)) }
    }
}
