// swift-tools-version:5.9
import PackageDescription

// Shared by the macOS app and the iOS remote: schedule and presence logic, plus the remote protocol.
let package = Package(
    name: "KeepGreenKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "KeepGreenKit", targets: ["KeepGreenKit"]),
    ],
    targets: [
        .target(name: "KeepGreenKit"),
        .testTarget(name: "KeepGreenKitTests", dependencies: ["KeepGreenKit"]),
    ]
)
