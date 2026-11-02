import Foundation

public enum WakeReason: String, CaseIterable, Sendable {
    case lid, userInput, network, scheduled, powerButton, other
}

public struct PowerEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case sleep, wake, darkWake }

    public var date: Date
    public var kind: Kind
    public var onBattery: Bool
    public var charge: Int
    public var reason: WakeReason?

    public init(date: Date, kind: Kind, onBattery: Bool, charge: Int, reason: WakeReason?) {
        self.date = date
        self.kind = kind
        self.onBattery = onBattery
        self.charge = charge
        self.reason = reason
    }
}

/// Parses the sleep and wake events out of `pmset -g log` text. Pure: no I/O.
public enum SleepLog {
    // Event line: timestamp, kind, padding spaces, then a tab. "Wake Requests" has
    // a word after "Wake", so it does not match.
    private static let eventLine = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [+-]\d{4}) (DarkWake|Sleep|Wake) *\t"#)
    private static let power = try! NSRegularExpression(
        pattern: #"Using (Batt|AC) \(Charge:(\d+)%\)"#, options: .caseInsensitive)
    private static let lidWord = try! NSRegularExpression(
        pattern: #"\blid\b"#, options: .caseInsensitive)

    public static func parse(_ text: String) -> [PowerEvent] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        var events: [PowerEvent] = []
        text.enumerateLines { line, _ in
            // Cheap rejection before any regex: most lines are not events.
            guard let first = line.utf8.first, first >= 0x30, first <= 0x39,
                  line.contains(" Sleep") || line.contains(" Wake") || line.contains(" DarkWake")
            else { return }

            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            guard let head = eventLine.firstMatch(in: line, range: full),
                  let date = formatter.date(from: ns.substring(with: head.range(at: 1))),
                  let p = power.firstMatch(in: line, range: full),
                  let charge = Int(ns.substring(with: p.range(at: 2)))
            else { return }

            let kind: PowerEvent.Kind
            switch ns.substring(with: head.range(at: 2)) {
            case "Sleep": kind = .sleep
            case "Wake": kind = .wake
            default: kind = .darkWake
            }
            let onBattery = ns.substring(with: p.range(at: 1)).caseInsensitiveCompare("AC") != .orderedSame

            var reason: WakeReason?
            if kind != .sleep {
                reason = classify(reasonText(in: line, powerStart: p.range.location, ns: ns))
            }
            events.append(PowerEvent(date: date, kind: kind, onBattery: onBattery, charge: charge, reason: reason))
        }
        return events
    }

    /// The text between "due to " and " Using"; empty if there is none.
    private static func reasonText(in line: String, powerStart: Int, ns: NSString) -> String {
        let marker = ns.range(of: "due to ")
        guard marker.location != NSNotFound else { return "" }
        let start = marker.location + marker.length
        // `powerStart` is the "Using" token; step back over the separating space.
        let end = powerStart - 1
        guard end > start else { return "" }
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    private static func classify(_ text: String) -> WakeReason {
        let lower = text.lowercased()
        if lidWord.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil {
            return .lid
        }
        if lower.contains("power button") || lower.contains("pwrbtn") { return .powerButton }
        if lower.contains("hid") || lower.contains("multi-touch") || lower.contains("keyboard") { return .userInput }
        if lower.contains("wifi") || lower.contains("arpt") || lower.contains("network") || lower.contains("en0") {
            return .network
        }
        if lower.contains("rtc") || lower.contains("maintenance") || lower.contains("scheduled") { return .scheduled }
        return .other
    }
}
