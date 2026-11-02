import Foundation

/// Runs a command-line tool off the main thread and returns its stdout, or `nil` on any
/// failure: launch error, non-zero exit, or the timeout (which terminates the process).
enum ProcessRunner {
    static let timeout: TimeInterval = 10

    static func run(_ path: String, _ arguments: [String]) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(path, arguments))
            }
        }
    }

    private static func runBlocking(_ path: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.timeout, execute: timeout)
        // Drain stdout before waiting: a large output (the pmset log is ~30k lines) would
        // otherwise fill the pipe buffer and block the child forever. A terminated child
        // closes its end, so this returns at the timeout too.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return data
    }
}

/// The text of `pmset -g log`, the source of the sleep report. The caller caches it
/// (see `ReportsModel.powerLogInterval`); the text never leaves the Mac.
struct PowerLogSource: Sendable {
    func read() async -> String? {
        guard let data = await ProcessRunner.run("/usr/bin/pmset", ["-g", "log"]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
