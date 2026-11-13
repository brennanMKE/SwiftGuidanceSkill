// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WeatherClient",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WeatherClient", targets: ["WeatherClient"]),
    ],
    targets: [
        .target(name: "HTTPCore"),
        .target(name: "WeatherClient", dependencies: ["HTTPCore"]),
    ]
)
