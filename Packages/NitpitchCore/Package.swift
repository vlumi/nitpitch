// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NitpitchCore",
    // Enables localized resources (String Catalogs) in this package's targets;
    // EN is the development/base language. Only English ships today — the
    // catalogs exist so adding a locale is a translation, not a refactor.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        // The watch app uses NitpitchCore + NitpitchData (pure Swift +
        // Accelerate + Foundation/Combine — they port as-is, which is what
        // makes the watch standalone). The NitpitchKit product is iOS/macOS:
        // its capture and views assume AVCaptureDevice and screens with room
        // for editors.
        .watchOS(.v10),
    ],
    products: [
        // Pure DSP + music theory — no AVFoundation, no UI. Headlessly testable.
        .library(name: "NitpitchCore", targets: ["NitpitchCore"]),
        // The app's state: stores, settings, and iCloud sync — Foundation +
        // Combine only, so it ports everywhere NitpitchCore does (the watch
        // is the second device that makes sync earn its keep).
        .library(name: "NitpitchData", targets: ["NitpitchData"]),
        // Audio capture (AVAudioEngine) + SwiftUI. iOS/macOS.
        .library(name: "NitpitchKit", targets: ["NitpitchKit"]),
    ],
    targets: [
        .target(
            name: "NitpitchCore",
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "NitpitchData",
            dependencies: ["NitpitchCore"]
        ),
        .target(
            name: "NitpitchKit",
            dependencies: ["NitpitchCore", "NitpitchData"],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "NitpitchCoreTests",
            dependencies: ["NitpitchCore"]
        ),
        .testTarget(
            name: "NitpitchKitTests",
            dependencies: ["NitpitchKit"]
        ),
    ]
)
