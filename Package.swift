// swift-tools-version: 6.2
import PackageDescription

// Modules follow concerns (docs/low-level-design.md). The agent's side
// (ReviewLease, ReviewWire, ReviewCommand, ReviewCLI) never links the app's
// rules (ReviewCore, ReviewStore), and builds and tests without the app. Only
// ReviewApp is macOS UI code: every other module builds and tests on Linux. A
// module and a type never share a name.
let package = Package(
    name: "VideoReview",
    platforms: [.macOS(.v26)],
    products: [
        // `video-review`, not `VideoReview`: the app's executable has that
        // name. `make bundle` puts the command in `Contents/Helpers`.
        .executable(name: "video-review", targets: ["ReviewCLI"]),
    ],
    targets: [
        // Who holds app control and the lease's rules as a pure value, given
        // the time on each call. It depends on nothing.
        .target(name: "ReviewLease", path: "Sources/ReviewLease"),
        // The control protocol, the socket framing and the app identity.
        .target(name: "ReviewWire", dependencies: ["ReviewLease"], path: "Sources/ReviewWire"),
        // The command table of `video-review`, a library so it tests
        // without a process.
        .target(name: "ReviewCommand", dependencies: ["ReviewWire", "ReviewLease"], path: "Sources/ReviewCommand"),
        .executableTarget(name: "ReviewCLI", dependencies: ["ReviewCommand"], path: "Sources/ReviewCLI"),
        // The review's rules: comments, the queue, the states, the payload
        // and the outbox. Pure logic, given the time on each call.
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
        .testTarget(name: "ReviewWireTests", dependencies: ["ReviewWire", "ReviewLease"], path: "Tests/ReviewWireTests"),
        .testTarget(name: "ReviewLeaseTests", dependencies: ["ReviewLease"], path: "Tests/ReviewLeaseTests"),
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
        path: "Sources/ReviewApp",
        swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(
        name: "ReviewAppTests",
        dependencies: ["ReviewApp", "ReviewWire", "ReviewLease", "ReviewCore", "ReviewTranscript", "ReviewStore"],
        path: "Tests/ReviewAppTests",
        swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
]
#endif
