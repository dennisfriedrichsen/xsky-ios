// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "XSkyCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "XSkyCore", targets: ["XSkyCore"])
    ],
    targets: [
        .target(
            name: "XSkyCore",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "XSkyCoreTests",
            dependencies: ["XSkyCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
