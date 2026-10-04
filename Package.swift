// swift-tools-version: 6.2
import PackageDescription

// The modules of docs/low-level-design.md, one target each. This manifest is
// the guard between the two sides: the agent side (VRLease, VRWire, VRCommand,
// VRCLI) never links an app-side library, so it builds and tests without the
// app. The app-side libraries (VRReview, VRTranscript, VRStore) join the list
// with the ticket that writes their first file; only VRApp may depend on them.
let package = Package(
    name: "VideoReview",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "VideoReview", targets: ["VRApp"]),
        // Not `video-review`: `make bundle` copies it into the app under that
        // name, as Contents/Helpers/video-review.
        .executable(name: "video-review-cli", targets: ["VRCLI"]),
    ],
    targets: [
        // ── agent side ──
        .target(name: "VRLease"),
        .target(name: "VRWire", dependencies: ["VRLease"]),
        .target(name: "VRCommand", dependencies: ["VRWire", "VRLease"]),
        .executableTarget(name: "VRCLI", dependencies: ["VRCommand"]),

        // ── the app: the only UI code ──
        .executableTarget(name: "VRApp", dependencies: ["VRWire", "VRLease"]),

        .testTarget(name: "VRWireTests", dependencies: ["VRWire", "VRLease"]),
        .testTarget(name: "VRCommandTests", dependencies: ["VRCommand", "VRWire", "VRLease"]),
    ],
    swiftLanguageModes: [.v6]
)
