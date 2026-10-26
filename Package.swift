// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PixelWorkersHub",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything that doesn't need a window: reading sessions, recording hook events,
        // installing the hooks and finding a session's terminal tab.
        .target(name: "PixelWorkersCore"),
        // The menu-bar app itself. The same binary also answers Claude Code's hooks (--pixel-workers-hook).
        .executableTarget(name: "PixelWorkersHub", dependencies: ["PixelWorkersCore"]),
        .testTarget(name: "PixelWorkersCoreTests", dependencies: ["PixelWorkersCore"]),
    ]
)
