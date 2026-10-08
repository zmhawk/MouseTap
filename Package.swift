// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseEventProbe",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mouse-event-probe", targets: ["MouseEventProbe"])
    ],
    targets: [
        .executableTarget(name: "MouseEventProbe"),
        .testTarget(name: "MouseEventProbeTests", dependencies: ["MouseEventProbe"])
    ]
)
