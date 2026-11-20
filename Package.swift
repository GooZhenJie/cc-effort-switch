// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CcEffortSwitch",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "CcEffortSwitchCore"),
        .executableTarget(
            name: "CcEffortSwitch",
            dependencies: ["CcEffortSwitchCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])]
        ),
        .testTarget(name: "CcEffortSwitchCoreTests", dependencies: ["CcEffortSwitchCore"]),
    ]
)
