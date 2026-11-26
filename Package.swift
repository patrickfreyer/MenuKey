// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JumpKey",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "JumpKey",
            path: "Sources/JumpKey",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
