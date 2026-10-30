// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpiderSolitaire",
    // English is the source language; translations live in the app's Resources/Localization/<lang>.lproj.
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpiderCore", targets: ["SpiderCore"]),
        .library(name: "SpiderBoard", targets: ["SpiderBoard"]),
        .library(name: "SpiderPersistence", targets: ["SpiderPersistence"]),
        .library(name: "SpiderUpdates", targets: ["SpiderUpdates"]),
        .executable(name: "SpiderSolitaire", targets: ["SpiderSolitaire"]),
        .executable(name: "SpiderIcon", targets: ["SpiderIcon"]),
    ],
    targets: [
        .target(name: "SpiderCore"),
        // Pure-Swift board geometry and pointer handling (no SwiftUI), testable on Linux.
        .target(
            name: "SpiderBoard", dependencies: ["SpiderCore"],
            linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]),
        // JSON files in Application Support (Foundation only, testable on Linux).
        .target(name: "SpiderPersistence", dependencies: ["SpiderCore"]),
        // Update check logic: versions, GitHub release JSON, policy (Foundation only, testable on Linux).
        .target(name: "SpiderUpdates"),
        // Resources/Cards: the Classic card faces (CC0 art, see Resources/Cards/CREDITS.md).
        // Resources/Localization: Localizable.strings / .stringsdict per language (en, de).
        .executableTarget(
            name: "SpiderSolitaire", dependencies: ["SpiderCore", "SpiderBoard", "SpiderPersistence", "SpiderUpdates"],
            resources: [.copy("Resources/Cards"), .process("Resources/Localization")]),
        // Renders the 1024 px app icon PNG (CoreGraphics); used by scripts/package.sh.
        .executableTarget(name: "SpiderIcon", dependencies: ["SpiderBoard", "SpiderCore"]),
        // Developer tool (not shipped): solver benchmarks and the bundled winnable-seed list.
        .executableTarget(
            name: "SpiderTools", dependencies: ["SpiderCore", "SpiderBoard"],
            linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]),
        .testTarget(name: "SpiderCoreTests", dependencies: ["SpiderCore"]),
        .testTarget(name: "SpiderBoardTests", dependencies: ["SpiderBoard", "SpiderCore"]),
        .testTarget(name: "SpiderPersistenceTests", dependencies: ["SpiderPersistence", "SpiderCore"]),
        .testTarget(name: "SpiderUpdatesTests", dependencies: ["SpiderUpdates"]),
        // Checks the app's string tables against each other, the app sources and the shared modules' texts.
        .testTarget(
            name: "SpiderLocalizationTests", dependencies: ["SpiderCore", "SpiderBoard", "SpiderUpdates"]),
    ]
)
