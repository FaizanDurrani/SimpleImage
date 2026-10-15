// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SimpleImage",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SimpleImage",
            targets: ["SimpleImage"]
        ),
        .library(
          name: "SimpleImageURLSessionLoader",
          targets: ["SimpleImageURLSessionLoader"]
        ),
        .library(
          name: "SimpleImageCache",
          targets: ["SimpleImageCache"]
        ),
        .library(
          name: "SimpleImageUIKit",
          targets: ["SimpleImageUIKit"]
        ),
        .library(
          name: "SimpleImageFLAnimatedImage",
          targets: ["SimpleImageFLAnimatedImage"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Flipboard/FLAnimatedImage.git", from: "1.0.16"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SimpleImage",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "SimpleImageURLSessionLoader",
            dependencies: ["SimpleImage"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "SimpleImageCache",
            dependencies: ["SimpleImage"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "SimpleImageUIKit",
            dependencies: ["SimpleImage"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "SimpleImageFLAnimatedImage",
            dependencies: ["SimpleImage", "SimpleImageUIKit", "FLAnimatedImage"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "SimpleImageTests",
            dependencies: ["SimpleImage", "SimpleImageUIKit", "SimpleImageCache", "SimpleImageFLAnimatedImage", "SimpleImageURLSessionLoader"],
            path: "Tests/SimpleImageProtocolTests",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
