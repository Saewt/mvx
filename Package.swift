// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mvx",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "Mvx", targets: ["Mvx"]),
    ],
    targets: [
        .target(
            name: "Mvx",
            path: "app",
            exclude: [
                "diagnostics/fixtures",
                "launcher",
            ]
        ),
        .testTarget(
            name: "MvxTests",
            dependencies: ["Mvx"],
            path: "tests"
        ),
    ]
)
