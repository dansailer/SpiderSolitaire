// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpiderSolitaire",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpiderCore", targets: ["SpiderCore"]),
        .executable(name: "SpiderSolitaire", targets: ["SpiderSolitaire"]),
    ],
    targets: [
        .target(name: "SpiderCore"),
        .executableTarget(name: "SpiderSolitaire", dependencies: ["SpiderCore"]),
        .testTarget(name: "SpiderCoreTests", dependencies: ["SpiderCore"]),
    ]
)
