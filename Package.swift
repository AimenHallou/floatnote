// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatNote",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FloatNote",
            path: "Sources/FloatNote",
            exclude: ["Resources"]
        )
    ]
)
