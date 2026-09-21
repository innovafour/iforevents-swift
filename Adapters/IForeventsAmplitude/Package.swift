// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IForeventsAmplitude",
    platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v7)],
    products: [.library(name: "IForeventsAmplitude", targets: ["IForeventsAmplitude"])],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/amplitude/Amplitude-Swift.git", from: "1.19.0"),
    ],
    targets: [
        .target(name: "IForeventsAmplitude", dependencies: [
            .product(name: "IForevents", package: "iforevents-swift"),
            .product(name: "AmplitudeSwift", package: "Amplitude-Swift"),
        ]),
        .testTarget(name: "IForeventsAmplitudeTests", dependencies: ["IForeventsAmplitude"]),
    ],
    swiftLanguageVersions: [.v5]
)
