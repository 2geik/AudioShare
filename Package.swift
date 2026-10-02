// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AudioShare",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AudioShare",
            path: "Sources/AudioShare",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
