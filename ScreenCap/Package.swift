// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenCap",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "ScreenCap",
            dependencies: ["HotKey"],
            path: "Sources",
            resources: [
                .process("../Resources")
            ]
        )
    ]
)
