// swift-tools-version: 6.0
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
        .package(url: "https://www.github.com/Vaida12345/DetailedDescription", from: "1.0.0"),
        .package(url: "https://www.github.com/Vaida12345/FinderItem", from: "1.0.0"),
        .package(url: "https://www.github.com/Vaida12345/ConcurrentStream", from: "0.1.0"),
        .package(url: "https://www.github.com/Vaida12345/NativeImage", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MIDIKit",
            dependencies: ["DetailedDescription", "FinderItem", "ConcurrentStream", "NativeImage"],
            path: "Sources",
            resources: [.copy("Engine/Nice-Steinway-Lite-v3.0.sf2")]
        ),
        .executableTarget(name: "Client", dependencies: ["MIDIKit"], path: "Client"),
        .testTarget(name: "Tests", dependencies: ["MIDIKit"], path: "Tests"),
    ],
    swiftLanguageModes: [.v5]
)
