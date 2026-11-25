// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MenuKey",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "MenuKey",
            path: "Sources/MenuKey",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
