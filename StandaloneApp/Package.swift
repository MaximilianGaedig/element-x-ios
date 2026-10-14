// swift-tools-version: 6.2

import PackageDescription

// The standalone Element X app built with xtool (Linux → iOS), from the same `ElementX` library that hosts such as
// Tunes embed. The Xcode project (project.yml) remains the upstream way to build it on a Mac.
let package = Package(
    name: "ElementXStandalone",
    platforms: [.iOS("18.5")],
    products: [
        .library(name: "ElementXStandalone", targets: ["ElementXStandalone"])
    ],
    dependencies: [
        .package(name: "Element Swift", path: "..")
    ],
    targets: [
        .target(name: "ElementXStandalone",
                dependencies: [.product(name: "ElementX", package: "Element Swift")],
                swiftSettings: [.define("ELEMENTX_STANDALONE_PACKAGE")])
    ]
)
