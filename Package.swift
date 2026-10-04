// swift-tools-version: 6.2
import PackageDescription

// Modules follow concerns (docs/low-level-design.md). The agent's side
// (ReviewWire, ReviewCommand, ReviewCLI) never links the app's rules, and
// builds and tests without the app. Only ReviewApp is macOS UI code. A
// module and a type never share a name.
let package = Package(
    name: "VideoReview",
    platforms: [.macOS(.v26)],
    products: [
        // `video-review`, not `VideoReview`: the app's executable has that
        // name. `make bundle` puts the command in `Contents/Helpers`.
        .executable(name: "video-review", targets: ["ReviewCLI"]),
        .executable(name: "VideoReview", targets: ["ReviewApp"]),
    ],
    targets: [
        // The control protocol, the socket framing and the app identity.
        .target(name: "ReviewWire", path: "Sources/ReviewWire"),
        // The command table of `video-review`, a library so it tests
        // without a process.
        .target(name: "ReviewCommand", dependencies: ["ReviewWire"], path: "Sources/ReviewCommand"),
        .executableTarget(name: "ReviewCLI", dependencies: ["ReviewCommand"], path: "Sources/ReviewCLI"),
        .executableTarget(name: "ReviewApp", dependencies: ["ReviewWire"], path: "Sources/ReviewApp"),
        .testTarget(name: "ReviewWireTests", dependencies: ["ReviewWire"], path: "Tests/ReviewWireTests"),
        .testTarget(
            name: "ReviewCommandTests",
            dependencies: ["ReviewWire", "ReviewCommand"],
            path: "Tests/ReviewCommandTests"
        ),
        .testTarget(name: "ReviewAppTests", dependencies: ["ReviewApp", "ReviewWire"], path: "Tests/ReviewAppTests"),
    ]
)
