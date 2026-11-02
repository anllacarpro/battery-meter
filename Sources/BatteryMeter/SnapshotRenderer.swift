import SwiftUI

/// Debug-only: `--render-snapshots <dir>` writes popover/empty-state PNGs in light and dark, then exits.
@MainActor
enum SnapshotRenderer {
    static var requestedDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(model: BatteryModel, to dir: URL) async {
        await model.loadHistory()
        model.refresh(record: false)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            write(PopoverView(model: model), scheme: scheme, to: dir.appending(path: "popover-\(suffix).png"))
            write(EmptyStateView().padding(16).frame(width: 300), scheme: scheme,
                  to: dir.appending(path: "empty-\(suffix).png"))
        }
        exit(0)
    }

    private static func write(_ view: some View, scheme: ColorScheme, to url: URL) {
        // Stand-in for the menu bar window's own material background.
        let background = scheme == .light ? Color(white: 0.96) : Color(white: 0.17)
        let renderer = ImageRenderer(content: view
            .background(background)
            .environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
