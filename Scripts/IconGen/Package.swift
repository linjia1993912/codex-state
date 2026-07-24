// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexStateIconGen",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CodexStateIconGen",
            path: "Sources/CodexStateIconGen"
        )
    ]
)
