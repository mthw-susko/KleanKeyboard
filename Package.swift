// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "KleanKeyboard",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "KleanKeyboard",
            path: "Sources/KleanKeyboard"
        )
    ]
)
