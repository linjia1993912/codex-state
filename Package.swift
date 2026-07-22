// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "codex-state",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexStateCore", targets: ["CodexStateCore"])
    ],
    targets: [
        .target(name: "CodexStateCore"),
        .testTarget(name: "CodexStateCoreTests", dependencies: ["CodexStateCore"])
    ],
    swiftLanguageModes: [.v6]
)
