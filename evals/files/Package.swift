// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "MediaKit", targets: ["MediaKit"])],
    targets: [
        .target(
            name: "MediaKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "MediaKitTests",
            dependencies: ["MediaKit"]
        )
    ]
)
