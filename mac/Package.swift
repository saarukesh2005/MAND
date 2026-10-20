// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MandMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MandCore", targets: ["MandCore"]),
        .executable(name: "MandMac", targets: ["MandMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.6.0"),
    ],
    targets: [
        // Platform-independent protocol logic, mirrored by android/core.
        .target(name: "MandCore"),
        // Networking, identity, pairing and app state for the Mac app.
        .target(
            name: "MandMacKit",
            dependencies: [
                "MandCore",
                .product(name: "X509", package: "swift-certificates"),
            ]
        ),
        // The SwiftUI app itself (thin layer over MandMacKit).
        .executableTarget(name: "MandMac", dependencies: ["MandMacKit"]),
        // Test-only helper for scripts/interop-test.sh (Swift server ↔ Java/Kotlin client). Not shipped.
        .executableTarget(name: "MandInteropServer", dependencies: ["MandMacKit", "MandCore"]),
        .testTarget(name: "MandCoreTests", dependencies: ["MandCore"]),
        .testTarget(name: "MandMacKitTests", dependencies: ["MandMacKit", "MandCore"]),
    ]
)
