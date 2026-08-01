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
    ],
    products: [
        // Pure DSP + music theory — no AVFoundation, no UI. Headlessly testable.
        .library(name: "NitpitchCore", targets: ["NitpitchCore"]),
        // Audio capture (AVAudioEngine) + SwiftUI. Depends on NitpitchCore.
        .library(name: "NitpitchKit", targets: ["NitpitchKit"]),
    ],
    targets: [
        .target(
            name: "NitpitchCore",
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "NitpitchKit",
            dependencies: ["NitpitchCore"],
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
