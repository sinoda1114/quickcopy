// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickCopy",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuickCopy", targets: ["QuickCopy"])
    ],
    targets: [
        .executableTarget(
            name: "QuickCopy",
            path: "Sources/QuickCopy"
        )
    ]
)
