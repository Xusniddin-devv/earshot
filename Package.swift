// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Earshot",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "earshot", targets: ["earshot"])],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7", traits: []),
    ],
    targets: [
        .target(name: "EarshotCore"),
        .target(name: "EarshotMac", dependencies: ["EarshotCore"]),
        .target(name: "EarshotVoice", dependencies: [
            "EarshotCore",
            .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .executableTarget(name: "earshot", dependencies: ["EarshotCore", "EarshotMac", "EarshotVoice"]),
        .testTarget(name: "EarshotCoreTests", dependencies: ["EarshotCore"]),
        .testTarget(name: "EarshotVoiceTests", dependencies: ["EarshotVoice"]),
    ],
    swiftLanguageModes: [.v5]
)
