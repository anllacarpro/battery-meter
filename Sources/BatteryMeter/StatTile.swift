import SwiftUI

struct StatTile: View {
    let title: String
    let value: String
    var caption: String? = nil
    /// Material on the window; Reports cards pass `ChartSurface.card`, since material on
    /// the card's own fill all but disappears in dark mode.
    var fill = AnyShapeStyle(.regularMaterial)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(fill, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
