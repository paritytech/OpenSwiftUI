// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "GTKRenderer",
    products: [
        .executable(name: "ExampleApp", targets: ["ExampleApp"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "ExampleApp",
            dependencies: [
                .product(name: "SwiftUI", package: "OpenSwiftUI"),
            ],
            path: "ExampleApp"
        ),
    ]
)
