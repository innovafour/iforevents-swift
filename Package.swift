// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IForevents",
    platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "IForevents", targets: ["IForevents"]),
    ],
    targets: [
        .target(name: "IForevents", path: "Sources/IForevents"),
        .testTarget(name: "IForeventsTests", dependencies: ["IForevents"], path: "Tests/IForeventsTests"),
    ],
    swiftLanguageVersions: [.v5]
)
