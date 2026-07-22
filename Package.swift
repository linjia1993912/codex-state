// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "codex-state",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexStateCore", targets: ["CodexStateCore"])
    ],
    targets: [
        .target(
            name: "CodexStateCore",
            resources: [.process("Pricing/Resources")]
        ),
        .testTarget(
            name: "CodexStateCoreTests",
            dependencies: ["CodexStateCore"],
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ]
        )
    ]
)
