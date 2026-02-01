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
            dependencies: ["RemixLib"],
            path: "Sources",
            exclude: ["remix.h"],
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Sources/remix.h"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L../../target/release",
                    "-lremix",
                    "-framework", "Accelerate",
                    "-framework", "AVFoundation",
                    "-framework", "CoreAudio"
                ])
            ]
        ),
        .systemLibrary(
            name: "RemixLib",
            path: ".",
            pkgConfig: nil,
            providers: nil
        )
    ]
)
