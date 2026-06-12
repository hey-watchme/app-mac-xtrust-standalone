// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "AppCore",
            targets: ["AppCore"]
        )
    ],
    targets: [
        .target(
            name: "AppCore",
            path: "Sources/AppCore"
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"],
            path: "Tests/AppCoreTests"
        )
    ]
)
