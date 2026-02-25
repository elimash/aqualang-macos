// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AquaLangMacOS",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AquaLangCore", targets: ["AquaLangCore"]),
        .executable(name: "AquaLangMac", targets: ["AquaLangMac"])
    ],
    targets: [
        .target(
            name: "AquaLangCore",
            path: "Sources/AquaLangCore"
        ),
        .executableTarget(
            name: "AquaLangMac",
            dependencies: ["AquaLangCore"],
            path: "Sources/AquaLangMac"
        ),
        .testTarget(
            name: "AquaLangCoreTests",
            dependencies: ["AquaLangCore"],
            path: "Tests/AquaLangCoreTests"
        )
    ]
)
