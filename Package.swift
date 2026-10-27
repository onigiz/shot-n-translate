// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShotNTranslate",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "ShotNTranslate", targets: ["ShotNTranslate"])
    ],
    targets: [
        .target(name: "ShotNTranslateCore"),
        .executableTarget(
            name: "ShotNTranslate",
            dependencies: ["ShotNTranslateCore"]
        ),
        .executableTarget(
            name: "ShotNTranslateChecks",
            dependencies: ["ShotNTranslateCore"]
        )
    ]
)
