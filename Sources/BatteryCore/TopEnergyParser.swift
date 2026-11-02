import Foundation

public struct ProcessPower: Equatable, Sendable {
    public var pid: Int32
    public var command: String
    public var power: Double

    public init(pid: Int32, command: String, power: Double) {
        self.pid = pid
        self.command = command
        self.power = power
    }
}

/// Parses the text of `top -l 2 -o power -stats pid,command,power`.
public enum TopEnergyParser {
    /// Returns rows of the second sample only (the first has no meaningful deltas).
    /// Skips `top` itself and rows with no power. No second sample gives `[]`.
    public static func parse(_ output: String) -> [ProcessPower] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        var headers = 0
        var result: [ProcessPower] = []
        var inRows = false
        for line in lines {
            if !inRows {
                if line.hasPrefix("PID") {
                    headers += 1
                    inRows = headers == 2
                }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            guard let row = parseRow(line), row.command != "top", row.power > 0 else { continue }
            result.append(row)
        }
        return result
    }

    /// The pid is the leading integer and the power the last number; the command is
    /// everything between them (it may contain spaces).
    private static func parseRow(_ line: Substring) -> ProcessPower? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(where: \.isWhitespace),
              let pid = Int32(trimmed[..<firstSpace]) else { return nil }
        let rest = trimmed[firstSpace...].trimmingCharacters(in: .whitespaces)
        guard let lastSpace = rest.lastIndex(where: \.isWhitespace),
              let power = Double(rest[rest.index(after: lastSpace)...]) else { return nil }
        let command = rest[..<lastSpace].trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return nil }
        return ProcessPower(pid: pid, command: command, power: power)
    }
}
