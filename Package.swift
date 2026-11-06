// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClientVersion",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [.library(name: "ClientVersion", targets: ["ClientVersion"])],
    targets: [
        .target(name: "ClientVersion"),
        .testTarget(name: "ClientVersionTests", dependencies: ["ClientVersion"]),
    ]
)
