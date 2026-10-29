// swift-tools-version: 5.9
//
// SwiftPM cannot run cargo during the build (tool plugins are sandboxed).
// Rust is shipped as a prebuilt XCFramework (see ../../../scripts/build_darwin_xcframework.sh).
// CocoaPods still builds from source via cargokit; see ../rhttp.podspec.

import PackageDescription

let package = Package(
    name: "rhttp",
    platforms: [
        .iOS("11.0"),
    ],
    products: [
        .library(name: "rhttp", targets: ["rhttp"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .binaryTarget(
            name: "RhttpRust",
            path: "rhttp.xcframework"
        ),
        .target(
            name: "rhttp",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "RhttpRust",
            ],
            path: "Sources/rhttp"
        ),
    ]
)
