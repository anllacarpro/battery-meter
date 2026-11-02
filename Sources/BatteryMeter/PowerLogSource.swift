import Foundation

/// Runs a command-line tool off the main thread and returns its stdout, or `nil` on any
/// failure: launch error, read error, no output, non-zero exit, or the timeout (which
/// terminates the process, then kills it if it ignores that).
enum ProcessRunner {
    static let timeout: TimeInterval = 10
    /// How long a child gets to exit after SIGTERM before it is sent SIGKILL.
    static let killGrace: TimeInterval = 2

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

        let pid = process.processIdentifier
        let timeout = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
            // A child that ignores SIGTERM would otherwise hold the read below (and the
            // caller, such as the energy sampler) forever.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.killGrace) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.timeout, execute: timeout)
        // Drain stdout before waiting: a large output (the pmset log is ~30k lines) would
        // otherwise fill the pipe buffer and block the child forever. A terminated child
        // closes its end, so this returns at the timeout too.
        // `readToEnd()` throws on a read error instead of raising an exception; it gives nil
        // for no output, which these tools never legitimately produce, so both count as failure.
        let data = try? stdout.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0, let data else { return nil }
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
