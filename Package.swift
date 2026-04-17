// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mytty",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "MyttyShared", path: "MyttyShared"),
        .executableTarget(
            name: "Mytty",
            dependencies: [
                "GhosttyKit",
                "MyttyShared",
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Mytty",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Carbon"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Mytty/Resources/Info.plist",
                ]),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "vendor/ghostty/macos/GhosttyKit.xcframework"
        ),
        .executableTarget(
            name: "MyttyCLI",
            dependencies: [
                "MyttyShared",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "MyttyCLI"
        ),
        .testTarget(
            name: "MyttyTests",
            dependencies: ["Mytty", "MyttyShared"],
            path: "MyttyTests"
        )
    ]
)
