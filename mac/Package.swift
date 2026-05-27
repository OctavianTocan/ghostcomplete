// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GhostComplete",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GhostComplete", targets: ["GhostComplete"])
    ],
    targets: [
        .executableTarget(
            name: "GhostComplete",
            path: "Sources/GhostComplete"
        ),
        .testTarget(
            name: "GhostCompleteTests",
            dependencies: ["GhostComplete"],
            path: "Tests/GhostCompleteTests"
        )
    ]
)
