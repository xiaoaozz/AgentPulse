// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AgentPulse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentPulse", targets: ["AgentPulse"]),
        .library(name: "AgentPulseCore", targets: ["AgentPulseCore"]),
    ],
    targets: [
        .target(
            name: "AgentPulseCore",
            path: "Platforms/macOS/Sources/AgentPulseCore"
        ),
        .executableTarget(
            name: "AgentPulse",
            dependencies: ["AgentPulseCore"],
            path: "Platforms/macOS/Sources/AgentPulse"
        ),
        .testTarget(
            name: "AgentPulseCoreTests",
            dependencies: ["AgentPulseCore"],
            path: "Platforms/macOS/Tests/AgentPulseCoreTests"
        ),
    ]
)
