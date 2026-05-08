// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [
        .macOS(.v15)
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
