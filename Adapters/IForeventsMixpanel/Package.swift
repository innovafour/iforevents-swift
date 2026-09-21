// swift-tools-version:5.9
import PackageDescription

// Depends on the core by path during development; consumers resolve
// https://github.com/innovafour/iforevents-swift by version instead.
let package = Package(
    name: "IForeventsMixpanel",
    platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v7)],
    products: [.library(name: "IForeventsMixpanel", targets: ["IForeventsMixpanel"])],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/mixpanel/mixpanel-swift.git", from: "6.7.0"),
    ],
    targets: [
        .target(name: "IForeventsMixpanel", dependencies: [
            .product(name: "IForevents", package: "iforevents-swift"),
            .product(name: "Mixpanel", package: "mixpanel-swift"),
        ]),
        .testTarget(name: "IForeventsMixpanelTests", dependencies: ["IForeventsMixpanel"]),
    ],
    swiftLanguageVersions: [.v5]
)
