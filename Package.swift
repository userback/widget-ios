// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "UserbackSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "UserbackSDK",
            targets: ["UserbackSDK"]
        )
    ],
    targets: [
        .target(
            name: "UserbackSDK",
            path: "Sources/UserbackSDK"
        ),
        .testTarget(
            name: "UserbackSDKTests",
            dependencies: ["UserbackSDK"],
            path: "Tests/UserbackSDKTests"
        )
    ]
)
