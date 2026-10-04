// swift-tools-version: 6.2
import PackageDescription

// Modules follow concerns (docs/low-level-design.md, "Targets"). The agent
// side (VRLease, VRWire, VRCommand, VRCLI) never imports an app-side module,
// so it builds and tests without the app. Only VRApp is macOS UI code.
let package = Package(
    name: "video-review",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "VideoReview", targets: ["VRApp"]),
        .executable(name: "video-review", targets: ["VRCLI"]),
    ],
    targets: [
        .target(name: "VRLease"),
        .target(name: "VRWire", dependencies: ["VRLease"]),
        .target(name: "VRCommand", dependencies: ["VRWire", "VRLease"]),
        .executableTarget(name: "VRCLI", dependencies: ["VRCommand"]),
        .target(name: "VRReview"),
        .target(name: "VRTranscript"),
        .target(name: "VRStore", dependencies: ["VRReview", "VRTranscript"]),
        .executableTarget(name: "VRApp", dependencies: ["VRLease", "VRWire", "VRReview", "VRTranscript", "VRStore"]),
        .testTarget(name: "VRLeaseTests", dependencies: ["VRLease"]),
        .testTarget(name: "VRWireTests", dependencies: ["VRWire", "VRLease"]),
        .testTarget(name: "VRCommandTests", dependencies: ["VRCommand", "VRWire", "VRLease"]),
        .testTarget(name: "VRReviewTests", dependencies: ["VRReview"]),
        .testTarget(name: "VRTranscriptTests", dependencies: ["VRTranscript"]),
        .testTarget(name: "VRStoreTests", dependencies: ["VRStore", "VRReview", "VRTranscript"]),
        .testTarget(name: "VRAppTests", dependencies: ["VRApp", "VRCommand", "VRWire", "VRLease", "VRReview", "VRTranscript", "VRStore"]),
    ]
)
