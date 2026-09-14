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
        // A sibling checkout for now: the wrapper is young enough that both sides change together,
        // and a path dependency lets that happen without a release on every edit.
        .package(path: "../../../MakeMKVKit"),
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
