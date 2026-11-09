// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NTFSManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NTFSManager", path: "Sources/NTFSManager"),
        .testTarget(name: "NTFSManagerTests", dependencies: ["NTFSManager"])
    ]
)
