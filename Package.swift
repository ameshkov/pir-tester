// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
]

let package = Package(
    name: "pir-tester",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "PirTester",
            targets: ["PirTester"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.10.0"),
        .package(
            url: "https://github.com/apple/swift-homomorphic-encryption",
            branch: "release/1.1"
        ),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.5.0"
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "PirTester",
            dependencies: [
                "PIRServiceTesting",
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                ),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PIRServiceTesting",
            dependencies: [
                "PrivacyPass", "Util",
                .product(
                    name: "HomomorphicEncryptionProtobuf",
                    package: "swift-homomorphic-encryption"
                ),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(
                    name: "PrivateInformationRetrievalProtobuf",
                    package: "swift-homomorphic-encryption"
                ),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "PrivacyPass",
            dependencies: [
                "Util",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(name: "Util", swiftSettings: swiftSettings),
        .testTarget(
            name: "PirTesterTests",
            dependencies: ["PirTester"],
            swiftSettings: swiftSettings
        ),
    ]
)

#if canImport(Darwin)
// Set the minimum macOS version for the package
package.platforms = [
    .macOS(.v15)  // Constrained by swift-homomorphic-encryption
]
#endif
