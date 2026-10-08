// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseTap",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MouseTap", targets: ["MouseTap"])
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(name: "MouseTap", dependencies: [.product(name: "TOML", package: "swift-toml")]),
        .testTarget(name: "MouseTapTests", dependencies: ["MouseTap"])
    ]
)
