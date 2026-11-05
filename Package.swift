// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "quickpkg",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "quickpkg",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ]
        ),
    ]
)
