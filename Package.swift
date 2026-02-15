// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "quickpkg",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "0.0.1"),
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
