// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clockpane",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Clockpane",
            path: "Sources/Clockpane",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
