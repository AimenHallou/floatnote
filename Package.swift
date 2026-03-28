// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatNote",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown", from: "0.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .executableTarget(
            name: "FloatNote",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/FloatNote",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "FloatNoteTests",
            dependencies: [
                "FloatNote",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/FloatNoteTests"
        )
    ]
)
