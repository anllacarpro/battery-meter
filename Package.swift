// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BatteryMeter",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "BatteryCore"),
        .executableTarget(name: "BatteryMeter", dependencies: ["BatteryCore"]),
        .testTarget(
            name: "BatteryCoreTests",
            dependencies: ["BatteryCore"],
            // CLT ships TestingMacros without wiring the plugin path.
            swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]
        ),
    ]
)
