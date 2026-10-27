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
    ],
    targets: [
        .target(name: "SpiderCore"),
        // Pure-Swift board geometry and pointer handling (no SwiftUI), testable on Linux.
        .target(name: "SpiderBoard", dependencies: ["SpiderCore"]),
        // JSON files in Application Support (Foundation only, testable on Linux).
        .target(name: "SpiderPersistence", dependencies: ["SpiderCore"]),
        .executableTarget(name: "SpiderSolitaire", dependencies: ["SpiderCore", "SpiderBoard", "SpiderPersistence"]),
        .testTarget(name: "SpiderCoreTests", dependencies: ["SpiderCore"]),
        .testTarget(name: "SpiderBoardTests", dependencies: ["SpiderBoard", "SpiderCore"]),
        .testTarget(name: "SpiderPersistenceTests", dependencies: ["SpiderPersistence", "SpiderCore"]),
    ]
)
