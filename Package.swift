// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ObservationsMigrationKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "ObservationsMigrationKit",
            targets: ["ObservationsMigrationKit"]
        )
    ],
    targets: [
        .target(name: "ObservationsMigrationKit"),
        .testTarget(
            name: "ObservationsMigrationKitTests",
            dependencies: ["ObservationsMigrationKit"]
        )
    ]
)
