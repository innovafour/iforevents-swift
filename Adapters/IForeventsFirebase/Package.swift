// swift-tools-version:5.9
import PackageDescription

// FirebaseAnalytics ships as a binary framework; the package resolves it from
// firebase-ios-sdk. Needs the app's GoogleService-Info.plist at runtime.
let package = Package(
    name: "IForeventsFirebase",
    platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v13)],
    products: [.library(name: "IForeventsFirebase", targets: ["IForeventsFirebase"])],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "11.0.0"),
    ],
    targets: [
        .target(name: "IForeventsFirebase", dependencies: [
            .product(name: "IForevents", package: "iforevents-swift"),
            .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
        ]),
    ],
    swiftLanguageVersions: [.v5]
)
