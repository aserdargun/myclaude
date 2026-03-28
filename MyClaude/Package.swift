// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MyClaude",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MyClaude",
            path: ".",
            exclude: ["Tests", "Package.swift"],
            resources: [
                .copy("Info.plist")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "MyClaudeTests",
            dependencies: ["MyClaude"],
            path: "Tests"
        )
    ]
)
