// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClaudeUsageTracker",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageTracker",
            path: ".",
            exclude: ["Tests", "Package.swift"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ClaudeUsageTrackerTests",
            dependencies: ["ClaudeUsageTracker"],
            path: "Tests"
        )
    ]
)
