// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Systems42Dashboard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Systems42Kit", targets: ["Systems42Kit"]),
        .library(name: "Systems42UI", targets: ["Systems42UI"]),
        .executable(name: "Systems42Dashboard", targets: ["Systems42Dashboard"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Systems42Kit",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        .target(name: "Systems42UI", dependencies: ["Systems42Kit"]),
        .executableTarget(
            name: "Systems42Dashboard",
            dependencies: ["Systems42UI", "Systems42Kit"]
        ),
        // Locates Tests/Fixtures and Tests/Golden for the test targets.
        .target(name: "Systems42TestSupport", path: "Tests/Systems42TestSupport"),
        .testTarget(
            name: "Systems42KitTests",
            dependencies: ["Systems42Kit", "Systems42TestSupport"]
        ),
        .testTarget(
            name: "Systems42UITests",
            dependencies: ["Systems42UI", "Systems42TestSupport"]
        ),
    ]
)
