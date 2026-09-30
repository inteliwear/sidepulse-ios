// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SidePulseTokenFormatting",
    products: [
        .library(name: "SidePulseTokenFormatting", targets: ["SidePulseTokenFormatting"])
    ],
    targets: [
        .target(
            name: "SidePulseTokenFormatting",
            path: "SidePulse",
            exclude: [
                "AppDelegate.swift", "AppModel.swift", "Assets.xcassets", "ContentView.swift",
                "DriveWriter.swift", "EventLog.swift", "FolderPicker.swift", "Info.plist",
                "PatternLibraryIntent.swift", "PatternLibraryViews.swift", "PatternPreviewWeb",
                "PatternThumbnailRenderer.swift", "PatternThumbnailSampler.mm", "PatternThumbnailSampler.h",
                "SidePulse-Bridging-Header.h", "SidePulse.entitlements", "SidePulseApp.swift", "WriteLEDsIntent.swift"
            ],
            sources: ["PushTokenFormatter.swift", "PairingRegistrationGate.swift", "PatternLibrary.swift", "PushKeyRegistry.swift", "PushPayload.swift"]
        ),
        .testTarget(
            name: "SidePulseTokenFormattingTests",
            dependencies: ["SidePulseTokenFormatting"],
            path: "Tests/SidePulseTokenFormattingTests"
        )
    ]
)
