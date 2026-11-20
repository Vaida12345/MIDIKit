// swift-tools-version: 6.4
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
        .package(url: "https://github.com/Vaida12345/DetailedDescription.git", from: "2.1.1"),
        .package(url: "https://github.com/Vaida12345/FinderItem.git", from: "2.4.2"),
        .package(url: "https://github.com/Vaida12345/ConcurrentStream.git", from: "1.0.2"),
        .package(url: "https://github.com/Vaida12345/NativeImage.git", from: "1.0.3"),
        .package(url: "https://github.com/Vaida12345/Optimization.git", from: "1.1.0"),
        .package(url: "https://github.com/Vaida12345/Essentials.git", from: "1.2.1"),
        .package(url: "https://github.com/Vaida12345/ColorComponents.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "MIDIKit",
            dependencies: ["DetailedDescription", "FinderItem", "ConcurrentStream", "NativeImage", "Optimization", "Essentials", "ColorComponents", "Intervals"],
            path: "Sources"
        ),
        .target(
            name: "IndexedTrack",
            dependencies: ["DetailedDescription", "Optimization", "Essentials", "MIDIKit", "Intervals"],
            path: "IndexedTrack"
        ),
        .target(
            name: "Intervals",
            path: "Intervals"
        ),
        .executableTarget(
            name: "Client",
            dependencies: ["MIDIKit", "IndexedTrack"],
            path: "Client"
        ),
        .testTarget(name: "Tests", dependencies: ["MIDIKit", "Intervals", "IndexedTrack"], path: "Tests"),
    ],
    
)
