// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShortcutPhone",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ShortcutPhone", targets: ["ShortcutPhoneApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.28.0"),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.8.0"),
        // Already a transitive dependency of Hummingbird; declared for NIOCore.SocketAddress.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.105.0"),
    ],
    targets: [
        .target(name: "ShortcutPhoneCore"),
        .target(name: "ShortcutPhoneMac", dependencies: ["ShortcutPhoneCore"]),
        .target(
            name: "ShortcutPhoneServer",
            dependencies: [
                "ShortcutPhoneCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "ShortcutPhoneApp",
            dependencies: [
                "ShortcutPhoneCore", "ShortcutPhoneMac", "ShortcutPhoneServer",
                "Sparkle",
            ],
            linkerSettings: [
                // Finds Sparkle.framework in Contents/Frameworks of the app bundle.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // Automatic updates: Sparkle's official prebuilt framework, fetched and checksum-verified
        // by scripts/fetch-sparkle.sh. scripts/bundle.sh embeds it in the app.
        .binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework"),
        .testTarget(
            name: "ShortcutPhoneCoreTests",
            dependencies: ["ShortcutPhoneCore"]
        ),
        .testTarget(
            name: "ShortcutPhoneMacTests",
            dependencies: ["ShortcutPhoneMac"]
        ),
        .testTarget(
            name: "ShortcutPhoneServerTests",
            dependencies: [
                "ShortcutPhoneServer",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
