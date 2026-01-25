// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Remix",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Remix", targets: ["Remix"])
    ],
    targets: [
        .executableTarget(
            name: "Remix",
            dependencies: ["MusicToolLib"],
            path: "Sources",
            exclude: ["music_tool.h"],
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Sources/music_tool.h"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L../../target/release",
                    "-lmusic_tool",
                    "-framework", "Accelerate",
                    "-framework", "AVFoundation",
                    "-framework", "CoreAudio"
                ])
            ]
        ),
        .systemLibrary(
            name: "MusicToolLib",
            path: ".",
            pkgConfig: nil,
            providers: nil
        )
    ]
)
