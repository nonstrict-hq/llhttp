// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "llhttp",
    platforms: [
        .iOS(.v13),
        .macCatalyst(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .visionOS(.v1),
        .watchOS(.v6)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "llhttp",
            targets: ["llhttp"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "llhttp",
            dependencies: ["Cllhttp"]
        ),
        .target(
            name: "Cllhttp",
            dependencies: [],
            exclude: [
                "./CMakeLists.txt",
                "./common.gypi",
                "./libllhttp.pc.in",
                "./LICENSE",
                "./LICENSE-MIT",
                "./llhttp.gyp",
                "./README.md",
            ],
            sources: [
                "./src"
            ],
            cSettings: [
                .headerSearchPath("./include"),
            ]
        ),
        .testTarget(
            name: "llhttpTests",
            dependencies: ["llhttp"]
        ),
    ]
)
