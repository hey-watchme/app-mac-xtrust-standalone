// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XTrustMacLocalFirst",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "AppCore",
            targets: ["AppCore"]
        ),
        .executable(
            name: "XTrustMacApp",
            targets: ["XTrustMacApp"]
        ),
    ],
    targets: [
        .target(
            name: "AppCore",
            path: "Packages/AppCore/Sources/AppCore"
        ),
        .executableTarget(
            name: "XTrustMacApp",
            dependencies: ["AppCore"],
            path: "XTrustMacApp"
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"],
            path: "Packages/AppCore/Tests/AppCoreTests"
        ),
        .testTarget(
            name: "AppCoreIntegrationTests",
            dependencies: ["AppCore"],
            path: "Tests/AppCoreIntegrationTests"
        ),
    ]
)
