// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TTSService",
    platforms: [.macOS(.v15)],
    products: [
        // Reusable server core, embedded by the SayTTS menu bar app.
        .library(name: "TTSServerKit", targets: ["TTSServerKit"]),
        // Standalone CLI / launchd service.
        .executable(name: "TTSServer", targets: ["TTSServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "TTSServerKit",
            dependencies: [.product(name: "Hummingbird", package: "hummingbird")],
            path: "Sources/TTSServerKit"
        ),
        .executableTarget(
            name: "TTSServer",
            dependencies: ["TTSServerKit"],
            path: "Sources/TTSServer"
        ),
        .testTarget(
            name: "TTSServerKitTests",
            dependencies: [
                "TTSServerKit",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/TTSServerKitTests"
        ),
    ]
)
