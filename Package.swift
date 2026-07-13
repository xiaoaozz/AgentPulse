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
        .target(name: "AgentPulseCore"),
        .executableTarget(name: "AgentPulse", dependencies: ["AgentPulseCore"]),
        .testTarget(name: "AgentPulseCoreTests", dependencies: ["AgentPulseCore"]),
    ]
)
