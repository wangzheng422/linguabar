// swift-tools-version: 5.10
// AI-Author: Codex (OpenAI gpt-5.6-sol)
import PackageDescription

let package = Package(
    name: "LinguaBar",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "LinguaBar", targets: ["LinguaBar"]),
    ],
    targets: [
        .executableTarget(
            name: "LinguaBar",
            path: "Sources/LinguaBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Speech"),
                .linkedFramework("Translation"),
            ]
        ),
        .testTarget(
            name: "LinguaBarTests",
            dependencies: ["LinguaBar"],
            path: "Tests/LinguaBarTests"
        ),
    ]
)
