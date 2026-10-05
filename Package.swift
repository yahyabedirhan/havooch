// swift-tools-version: 6.2
import PackageDescription

// Modules follow concerns (docs/low-level-design.md). The agent's side
// (ReviewWire, ReviewLease, ReviewCommand, ReviewCLI) never links the app's rules
// (ReviewCore, ReviewStore), and builds and tests without the app. Only
// ReviewApp is macOS UI code. A module and a type never share a name.
let package = Package(
    name: "VideoReview",
    platforms: [.macOS(.v26)],
    products: [
        // `video-review`, not `VideoReview`: the app's executable has that
        // name. `make bundle` puts the command in `Contents/Helpers`.
        .executable(name: "video-review", targets: ["ReviewCLI"]),
    ],
    targets: [
        // The control protocol, the socket framing and the app identity.
        .target(name: "ReviewWire", path: "Sources/ReviewWire"),
        // The lease's rules as a pure value, given the time on each call.
        .target(name: "ReviewLease", dependencies: ["ReviewWire"], path: "Sources/ReviewLease"),
        // The command table of `video-review`, a library so it tests
        // without a process.
        .target(name: "ReviewCommand", dependencies: ["ReviewWire", "ReviewLease"], path: "Sources/ReviewCommand"),
        .executableTarget(name: "ReviewCLI", dependencies: ["ReviewCommand"], path: "Sources/ReviewCLI"),
        // The spec's "Review" module: comments, the queue and the comment
        // states. Pure logic.
        .target(name: "ReviewCore", path: "Sources/ReviewCore"),
        // The `Transcriber` interface, its three sources and the window cut.
        .target(name: "ReviewTranscript", path: "Sources/ReviewTranscript"),
        // What's kept on disk, by the content hash of the video.
        .target(name: "ReviewStore", dependencies: ["ReviewCore", "ReviewTranscript"], path: "Sources/ReviewStore"),
        .testTarget(name: "ReviewTranscriptTests", dependencies: ["ReviewTranscript"], path: "Tests/ReviewTranscriptTests"),
        .testTarget(name: "ReviewCoreTests", dependencies: ["ReviewCore"], path: "Tests/ReviewCoreTests"),
        .testTarget(
            name: "ReviewStoreTests", dependencies: ["ReviewCore", "ReviewTranscript", "ReviewStore"], path: "Tests/ReviewStoreTests"
        ),
        .testTarget(name: "ReviewWireTests", dependencies: ["ReviewWire"], path: "Tests/ReviewWireTests"),
        .testTarget(name: "ReviewLeaseTests", dependencies: ["ReviewWire", "ReviewLease"], path: "Tests/ReviewLeaseTests"),
        .testTarget(
            name: "ReviewCommandTests",
            dependencies: ["ReviewWire", "ReviewLease", "ReviewCommand"],
            path: "Tests/ReviewCommandTests"
        ),
    ]
)

// The app and its tests are macOS UI code. Elsewhere (a Linux machine) the
// package is the modules that build and test without the app.
#if os(macOS)
package.products.append(.executable(name: "VideoReview", targets: ["ReviewApp"]))
package.targets += [
    .executableTarget(
        name: "ReviewApp",
        dependencies: ["ReviewWire", "ReviewLease", "ReviewCore", "ReviewTranscript", "ReviewStore"],
        path: "Sources/ReviewApp"
    ),
    .testTarget(
        name: "ReviewAppTests",
        dependencies: ["ReviewApp", "ReviewWire", "ReviewLease", "ReviewCore", "ReviewTranscript", "ReviewStore"],
        path: "Tests/ReviewAppTests"
    ),
]
#endif
