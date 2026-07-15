// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AgentPulse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentPulse", targets: ["AgentPulse"]),
        .library(name: "AgentPulseCore", targets: ["AgentPulseCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2"),
    ],
    targets: [
        .target(name: "AgentPulseCore"),
        .executableTarget(
            name: "AgentPulse",
            dependencies: [
                "AgentPulseCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(name: "AgentPulseCoreTests", dependencies: ["AgentPulseCore"]),
    ]
)
