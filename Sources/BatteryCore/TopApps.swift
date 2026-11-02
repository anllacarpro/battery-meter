import Foundation

/// The apps drawing the most power in one sample.
public enum TopApps {
    /// Up to `limit` names by power, highest first. Rows sharing a name are summed first;
    /// empty names are skipped. Ties are broken by name so the order is stable.
    public static func names(from rows: [(name: String, power: Double)], limit: Int) -> [String] {
        var totals: [String: Double] = [:]
        for row in rows where !row.name.isEmpty {
            totals[row.name, default: 0] += row.power
        }
        return totals
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(max(limit, 0))
            .map(\.key)
    }
}
