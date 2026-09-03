// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GoVietShellCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GoVietShellCore", targets: ["GoVietShellCore"]),
    ],
    targets: [
        .target(
            name: "GoVietShellCore",
            path: "Sources",
            exclude: [
                "App.swift",
                "Bridge",
                "Inject/TextInjector.swift",
                "State/AppMonitor.swift",
                "State/SecureInputMonitor.swift",
                "State/SettingsStore.swift",
                "Tap/EventTapManager.swift",
                "UI",
                "Util",
            ],
            sources: [
                "Inject/AppProfiles.swift",
                "Inject/EventRouting.swift",
                "Inject/InjectionScheduler.swift",
                "Inject/TextInjectionPlan.swift",
                "State/HotkeyDetector.swift",
                "State/RuntimeState.swift",
                "Tap/EventTextDecoder.swift",
            ]
        ),
        .testTarget(
            name: "GoVietShellCoreTests",
            dependencies: ["GoVietShellCore"],
            path: "Tests/GoVietShellCoreTests"
        ),
    ]
)
