// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mark",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "MarkCore"),
        .executableTarget(name: "Mark", dependencies: ["MarkCore"]),
        .executableTarget(
            name: "MarkFinder",
            dependencies: [], // standalone on purpose: linking MarkCore would add its whole text engine to the extension
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(name: "MarkCoreTests", dependencies: ["MarkCore"]),
        .testTarget(name: "MarkTests", dependencies: ["Mark", "MarkCore"]),
    ]
)
