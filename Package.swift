// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.8.1")),
    .package(url: "https://github.com/element-hq/swift-command-line-tools.git", branch: "main"),
    // .package(path: "../swift-command-line-tools"),
    .package(url: "https://github.com/swiftlang/swift-subprocess", .upToNextMinor(from: "0.3.0")),
    .package(url: "https://github.com/jpsim/Yams", .upToNextMinor(from: "6.2.2")),
    .package(url: "https://github.com/apple/swift-log", .upToNextMinor(from: "1.10.1")),
    .package(url: "https://github.com/a7ex/xcresultparser", .upToNextMinor(from: "2.2.0")),

    // The app as a library (Tunes embeds it), versions as in project.yml.
    .package(url: "https://github.com/element-hq/matrix-rust-components-swift", exact: "26.10.13"),
    .package(path: "compound-ios"),
    .package(path: "Components/BuildExtensions"),
    .package(url: "https://github.com/element-hq/element-call-ios", exact: "0.1.0-rc.10"),
    .package(url: "https://github.com/matrix-org/matrix-analytics-events", exact: "0.38.0"),
    .package(url: "https://github.com/element-hq/element-call-swift", exact: "0.26.1"),
    .package(url: "https://github.com/matrix-org/emojibase-bindings", revision: "60bc01f2e3b31445dc723f5af1a777b63d18e6c2"),
    .package(url: "https://github.com/element-hq/swift-ogg", exact: "0.0.4"),
    .package(url: "https://github.com/element-hq/matrix-rich-text-editor-swift", exact: "2.42.1"),
    .package(url: "https://github.com/apple/swift-algorithms", exact: "1.2.1"),
    .package(url: "https://github.com/apple/swift-async-algorithms", exact: "1.1.6"),
    .package(url: "https://github.com/apple/swift-collections", exact: "1.7.1"),
    .package(url: "https://github.com/devicekit/DeviceKit", exact: "5.9.0"),
    .package(url: "https://github.com/dmrschmidt/DSWaveformImage", exact: "14.5.0"),
    .package(url: "https://github.com/nicklockwood/GZIP", exact: "1.3.2"),
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", exact: "4.2.2"),
    .package(url: "https://github.com/onevcat/Kingfisher", exact: "8.13.0"),
    .package(url: "https://github.com/krzysztofzablocki/KZFileWatchers", exact: "1.2.0"),
    .package(url: "https://github.com/lukaskubanek/LoremSwiftum", exact: "2.2.3"),
    .package(url: "https://github.com/nicklockwood/LRUCache", exact: "1.3.0"),
    .package(url: "https://github.com/guoyingtao/Mantis", exact: "3.1.0"),
    .package(url: "https://github.com/PostHog/posthog-ios", exact: "3.85.3"),
    .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.29.2"),
    .package(url: "https://github.com/tevelee/SwiftUI-Flow.git", exact: "3.5.1"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9"),
    // Fork: upstream 6.0.1's test target overlaps its library sources, which SwiftPM refuses.
    .package(url: "https://github.com/MaximilianGaedig/SwiftState", revision: "0b80983"),
    .package(url: "https://github.com/mxcl/Version", exact: "2.2.1")
]

if FileManager.default.fileExists(atPath: "Enterprise/Pipeline/Package.swift") {
    dependencies.append(.package(path: "./Enterprise/Pipeline"))
}

/// The ElementX target lives at the package root so it can take files from outside `ElementX/Sources` (as the Xcode
/// target does). SwiftPM would otherwise treat every other file under the root as a resource, so everything that is
/// not on the way to one of these paths is excluded. Resources are compiled outside SwiftPM (ElementXResources.bundle).
let elementXSources = [
    "ElementX/Sources",
    "NSE/Sources",
    "Components/Secrets/Secrets.swift",
    "Tools/Scripts/Templates/SimpleScreenExample/ElementX"
]

func excludingAllBut(_ included: [String]) -> [String] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
    var excluded: [String] = []
    var parents: Set<String> = [""]
    for path in included {
        var components = path.split(separator: "/").map(String.init)
        components.removeLast()
        var prefix = ""
        for component in components {
            prefix = prefix.isEmpty ? component : prefix + "/" + component
            parents.insert(prefix)
        }
    }
    for parent in parents.sorted() {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: parent.isEmpty ? root : root + "/" + parent)) ?? []
        for entry in entries {
            let path = parent.isEmpty ? entry : parent + "/" + entry
            if !parents.contains(path), !included.contains(path) { excluded.append(path) }
        }
    }
    return excluded
}

let appSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances")
]

let package = Package(
    name: "Element Swift",
    platforms: [
        .macOS(.v15),
        .iOS("18.5")
    ],
    products: [
        .executable(name: "tools", targets: ["Tools"]),
        // The ElementX app target as a library for hosts built with SwiftPM (xtool): the host provides the
        // `App`/window (ElementXHost) and the Info.plist keys; resources come from ElementXResources.bundle.
        .library(name: "ElementX", targets: ["ElementX"])
    ],
    dependencies: dependencies,
    targets: [
        .executableTarget(name: "Tools",
                          dependencies: [
                            .product(name: "ArgumentParser", package: "swift-argument-parser"),
                            .product(name: "CommandLineTools", package: "swift-command-line-tools"),
                            .product(name: "Subprocess", package: "swift-subprocess"),
                            .product(name: "Yams", package: "Yams"),
                            .product(name: "Logging", package: "swift-log"),
                            .product(name: "XcresultparserLib", package: "xcresultparser")
                          ],
                          path: "Tools/Sources",
                          swiftSettings: [
                            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                            .enableUpcomingFeature("InferIsolatedConformances")
                          ]),
        .target(name: "MatrixRustSDKMocks",
                dependencies: [.product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")],
                path: "Components/SDKMocks/Sources"),
        .target(name: "MapLibreInterface",
                path: "Components/MapLibre/MapLibreInterface/Sources",
                swiftSettings: appSwiftSettings),
        .target(name: "ElementX",
                dependencies: [
                    "MatrixRustSDKMocks",
                    "MapLibreInterface",
                    .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift"),
                    .product(name: "Compound", package: "compound-ios"),
                    .product(name: "Macros", package: "BuildExtensions"),
                    .product(name: "Algorithms", package: "swift-algorithms"),
                    .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                    .product(name: "AnalyticsEvents", package: "matrix-analytics-events"),
                    .product(name: "Collections", package: "swift-collections"),
                    .product(name: "DeviceKit", package: "DeviceKit"),
                    .product(name: "EmbeddedElementCall", package: "element-call-swift"),
                    .product(name: "KeychainAccess", package: "KeychainAccess"),
                    .product(name: "Kingfisher", package: "Kingfisher"),
                    .product(name: "KZFileWatchers", package: "KZFileWatchers"),
                    .product(name: "LoremSwiftum", package: "LoremSwiftum"),
                    .product(name: "LRUCache", package: "LRUCache"),
                    .product(name: "Mantis", package: "Mantis"),
                    .product(name: "ElementCall", package: "element-call-ios"),
                    .product(name: "PostHog", package: "posthog-ios"),
                    .product(name: "SwiftState", package: "SwiftState"),
                    .product(name: "GZIP", package: "GZIP"),
                    .product(name: "Sentry", package: "sentry-cocoa"),
                    .product(name: "SentrySwiftUI", package: "sentry-cocoa"),
                    .product(name: "Version", package: "Version"),
                    .product(name: "Emojibase", package: "emojibase-bindings"),
                    .product(name: "WysiwygComposer", package: "matrix-rich-text-editor-swift"),
                    .product(name: "SwiftOGG", package: "swift-ogg"),
                    .product(name: "SwiftSoup", package: "SwiftSoup"),
                    .product(name: "Flow", package: "SwiftUI-Flow"),
                    .product(name: "DSWaveformImageViews", package: "DSWaveformImage")
                ],
                path: ".",
                exclude: excludingAllBut(elementXSources) + [
                    "ElementX/Sources/Application/Application.swift",
                    "ElementX/Sources/Other/Extensions/XCUIElement.swift",
                    "ElementX/Sources/Other/EffectsScene/ConfettiScene.scn"
                ],
                sources: elementXSources,
                swiftSettings: appSwiftSettings + [.define("IS_MAIN_APP")])
    ]
)
