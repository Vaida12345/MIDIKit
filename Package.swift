// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MIDIKit",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MIDIKit",
            targets: ["MIDIKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Vaida12345/DetailedDescription.git", branch: "main")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "MIDIKit", dependencies: ["DetailedDescription"]),
        .executableTarget(name: "Client", dependencies: ["MIDIKit"], path: "Client"),
        .testTarget(name: "Tests", dependencies: ["MIDIKit"], path: "Tests"),
    ]
)
