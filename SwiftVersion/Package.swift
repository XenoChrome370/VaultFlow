// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VaultFlow",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "VaultFlow", targets: ["VaultFlow"]),
        .library(name: "VaultFlowCore", targets: ["VaultFlowCore"])
    ],
    targets: [
        // All non-UI logic lives in VaultFlowCore so it can be unit tested
        // headlessly with `swift test`.
        .target(
            name: "VaultFlowCore",
            path: "Sources/VaultFlowCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("LocalAuthentication")
            ]
        ),
        .executableTarget(
            name: "VaultFlow",
            dependencies: ["VaultFlowCore"],
            path: "Sources/VaultFlow",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreText")
            ]
        ),
        .testTarget(
            name: "VaultFlowCoreTests",
            dependencies: ["VaultFlowCore"],
            path: "Tests/VaultFlowCoreTests",
            resources: [.copy("Fixtures")]
        )

    ]
)

for target in package.targets {
    target.swiftSettings = [.swiftLanguageMode(.v5)]
}
