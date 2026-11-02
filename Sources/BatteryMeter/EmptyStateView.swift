import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "battery.0percent")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No battery found")
                .font(.headline)
            Text("This Mac doesn’t have a battery to measure.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
