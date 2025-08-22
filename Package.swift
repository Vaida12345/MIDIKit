// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MIDIKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MIDIKit",
            targets: ["MIDIKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Vaida12345/DetailedDescription.git", from: "2.0.5"),
        .package(url: "https://github.com/Vaida12345/FinderItem.git", from: "1.0.16"),
        .package(url: "https://github.com/Vaida12345/ConcurrentStream.git", from: "1.0.1"),
        .package(url: "https://github.com/Vaida12345/NativeImage.git", from: "1.0.2"),
        .package(url: "https://github.com/Vaida12345/Optimization.git", from: "1.0.8"),
        .package(url: "https://github.com/Vaida12345/Essentials.git", from: "1.1.1")
    ],
    targets: [
        .target(
            name: "MIDIKit",
            dependencies: ["DetailedDescription", "FinderItem", "ConcurrentStream", "NativeImage", "Optimization", "Essentials"],
            path: "Sources"
        ),
        .executableTarget(name: "Client", dependencies: ["MIDIKit"], path: "Client"),
        .testTarget(name: "Tests", dependencies: ["MIDIKit"], path: "Tests"),
    ],
    
)
