// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Interval",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "IntervalCore", targets: ["IntervalCore"]),
        .executable(name: "Interval", targets: ["Interval"]),
    ],
    targets: [
        .target(name: "IntervalCore"),
        .executableTarget(name: "Interval", dependencies: ["IntervalCore"]),
        .testTarget(name: "IntervalCoreTests", dependencies: ["IntervalCore"]),
    ],
    swiftLanguageModes: [.v5]
)
