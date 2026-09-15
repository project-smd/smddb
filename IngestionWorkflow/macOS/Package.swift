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
        // VideoLAN's own package: one xcframework for every Apple platform, LGPL 2.1, linked as a
        // framework. The 4.0 line is still alpha, so pin the exact prerelease tag rather than a range.
        .package(url: "https://code.videolan.org/videolan/VLCKit.git", exact: "4.0.0-a24"),
    ],
    targets: [
        .executableTarget(
            name: "Ingest",
            dependencies: [
                .product(name: "MakeMKV", package: "MakeMKVKit"),
                .product(name: "MakeMKVRobot", package: "MakeMKVKit"),
                .product(name: "VLCKit", package: "VLCKit"),
            ]
        ),
        .testTarget(name: "IngestTests", dependencies: ["Ingest"]),
    ]
)
