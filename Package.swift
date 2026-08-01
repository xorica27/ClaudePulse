// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudePulse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClaudePulse", targets: ["ClaudePulse"]),
        .library(name: "ClaudePulseCore", targets: ["ClaudePulseCore"])
    ],
    targets: [
        .target(
            name: "ClaudePulseCore"
        ),
        .executableTarget(
            name: "ClaudePulse",
            dependencies: ["ClaudePulseCore"],
            path: "Sources/ClaudePulse",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "ClaudePulseTests",
            dependencies: ["ClaudePulseCore"]
        )
    ]
)
