// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MandMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MandCore", targets: ["MandCore"]),
        .library(name: "MandContext", targets: ["MandContext"]),
        .executable(name: "MandMac", targets: ["MandMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.6.0"),
        // Quick Share message format (Apache-2.0). Used only by the isolated MandQuickShare target.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.39.0"),
    ],
    targets: [
        // Platform-independent protocol logic, mirrored by android/core.
        .target(name: "MandCore"),
        // Continuity layer: context log, Task Capsules, Time Machine, Brain search (TECHNICAL_DECISIONS D22–D24).
        .target(name: "MandContext"),
        // Networking, identity, pairing and app state for the Mac app.
        .target(
            name: "MandMacKit",
            dependencies: [
                "MandCore",
                "MandContext",
                .product(name: "X509", package: "swift-certificates"),
            ]
        ),
        // Optional, unofficial Quick Share receiving (adapted from NearDrop, Unlicense). Isolated so it can
        // be removed without touching the rest of M’AND. Swift 5 mode: the adapted code predates Swift 6.
        .target(
            name: "MandQuickShare",
            dependencies: ["MandCore", .product(name: "SwiftProtobuf", package: "swift-protobuf")],
            exclude: ["NEARDROP_UNLICENSE.txt"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The SwiftUI app itself (thin layer over MandMacKit).
        .executableTarget(name: "MandMac", dependencies: ["MandMacKit", "MandQuickShare"]),
        // Test-only helper for scripts/interop-test.sh (Swift server ↔ Java/Kotlin client). Not shipped.
        .executableTarget(name: "MandInteropServer", dependencies: ["MandMacKit", "MandCore"]),
        .testTarget(name: "MandCoreTests", dependencies: ["MandCore"]),
        .testTarget(name: "MandContextTests", dependencies: ["MandContext"]),
        .testTarget(name: "MandMacKitTests", dependencies: ["MandMacKit", "MandCore"]),
        .testTarget(name: "MandQuickShareTests", dependencies: ["MandQuickShare", "MandCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
