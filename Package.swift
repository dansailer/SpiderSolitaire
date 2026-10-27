// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpiderSolitaire",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpiderCore", targets: ["SpiderCore"]),
        .library(name: "SpiderBoard", targets: ["SpiderBoard"]),
        .library(name: "SpiderPersistence", targets: ["SpiderPersistence"]),
        .executable(name: "SpiderSolitaire", targets: ["SpiderSolitaire"]),
        .executable(name: "SpiderIcon", targets: ["SpiderIcon"]),
    ],
    targets: [
        .target(name: "SpiderCore"),
        // Pure-Swift board geometry and pointer handling (no SwiftUI), testable on Linux.
        .target(name: "SpiderBoard", dependencies: ["SpiderCore"],
                linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]),
        // JSON files in Application Support (Foundation only, testable on Linux).
        .target(name: "SpiderPersistence", dependencies: ["SpiderCore"]),
        .executableTarget(name: "SpiderSolitaire", dependencies: ["SpiderCore", "SpiderBoard", "SpiderPersistence"]),
        // Renders the 1024 px app icon PNG (CoreGraphics); used by scripts/package.sh.
        .executableTarget(name: "SpiderIcon", dependencies: ["SpiderBoard"]),
        .testTarget(name: "SpiderCoreTests", dependencies: ["SpiderCore"]),
        .testTarget(name: "SpiderBoardTests", dependencies: ["SpiderBoard", "SpiderCore"]),
        .testTarget(name: "SpiderPersistenceTests", dependencies: ["SpiderPersistence", "SpiderCore"]),
    ]
)
