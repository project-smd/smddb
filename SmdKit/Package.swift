// swift-tools-version: 6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the smddb project authors

import PackageDescription

// The parts of smddb that are not an app: the container model, the file each container is kept as
// in the data repository, and the database behind them. A package of its own rather than a target
// in the macOS tool's, because the tool links VLCKit and MakeMKVKit, and a CI job that only wants
// to read container files must not have to resolve either. Nothing here imports anything Apple-only.
let package = Package(
    name: "SmdKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SmdKit", targets: ["SmdKit"]),
    ],
    targets: [
        .target(name: "SmdKit"),
        .testTarget(name: "SmdKitTests", dependencies: ["SmdKit"]),
    ]
)
