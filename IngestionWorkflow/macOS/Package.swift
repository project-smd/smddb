// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import PackageDescription

let package = Package(
    name: "IngestionWorkflow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ingest", targets: ["Ingest"]),
    ],
    dependencies: [
        // Tracked by branch rather than by version while the wrapper has no release: the two change
        // together, and a tag on every edit would be ceremony. Pin to a version once one exists.
        .package(url: "https://github.com/project-smd/MakeMKVKit.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Ingest",
            dependencies: [
                .product(name: "MakeMKV", package: "MakeMKVKit"),
                .product(name: "MakeMKVRobot", package: "MakeMKVKit"),
            ]
        ),
        .testTarget(name: "IngestTests", dependencies: ["Ingest"]),
    ]
)
