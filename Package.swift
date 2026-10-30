// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchHUD",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NotchHUDCore", targets: ["NotchHUDCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NotchHUDCore",
            path: "Sources/NotchHUDCore"
        ),
        .testTarget(
            name: "NotchHUDTests",
            dependencies: ["NotchHUDCore"],
            path: "Tests/NotchHUDTests"
        )
    ]
)
