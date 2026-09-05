// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Interval",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "IntervalCore", targets: ["IntervalCore"]),
        .executable(name: "Interval", targets: ["Interval"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "IntervalCore"),
        .executableTarget(name: "Interval", dependencies: [
            "IntervalCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ]),
        .testTarget(name: "IntervalCoreTests", dependencies: ["IntervalCore"]),
        .testTarget(name: "IntervalAppTests", dependencies: ["Interval", "IntervalCore"]),
    ],
    swiftLanguageModes: [.v5]
)
