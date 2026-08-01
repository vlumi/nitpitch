// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TunerCore",
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
        .library(name: "TunerCore", targets: ["TunerCore"]),
        // Audio capture (AVAudioEngine) + SwiftUI. Depends on TunerCore.
        .library(name: "TunerKit", targets: ["TunerKit"]),
    ],
    targets: [
        .target(
            name: "TunerCore",
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .target(
            name: "TunerKit",
            dependencies: ["TunerCore"],
            resources: [.process("Resources/Localizable.xcstrings")]
        ),
        .testTarget(
            name: "TunerCoreTests",
            dependencies: ["TunerCore"]
        ),
        .testTarget(
            name: "TunerKitTests",
            dependencies: ["TunerKit"]
        ),
    ]
)
