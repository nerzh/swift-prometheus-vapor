// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "prometeus-client",
    platforms: [
       .macOS(.v10_15)
    ],
//    pkgConfig: "",
//    providers: [
//        .apt(["dstat"])
//    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/MrLotU/SwiftPrometheus.git", from: "1.0.0-alpha"),
        .package(name: "SwiftExtensionsPack", url: "https://github.com/nerzh/swift-extensions-pack.git", .upToNextMajor(from: "0.4.1")),
        .package(name: "SwiftLinuxStat", url: "https://github.com/nerzh/SwiftLinuxStat.git", .upToNextMajor(from: "0.5.1")),
//        .package(name: "FileUtils", path: "/Users/nerzh/mydata/swift_projects/FileUtils"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SwiftPrometheus", package: "SwiftPrometheus"),
                .product(name: "SwiftExtensionsPack", package: "SwiftExtensionsPack"),
                .product(name: "SwiftLinuxStat", package: "SwiftLinuxStat"),
//                .product(name: "FileUtils", package: "FileUtils"),
            ],
            swiftSettings: [
                // Enable better optimizations when building in Release configuration. Despite the use of
                // the `.unsafeFlags` construct required by SwiftPM, this flag is recommended for Release
                // builds. See <https://github.com/swift-server/guides#building-for-production> for details.
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .target(name: "Run", dependencies: [.target(name: "App")]),
        .testTarget(name: "AppTests", dependencies: [
            .target(name: "App"),
            .product(name: "XCTVapor", package: "vapor"),
        ])
    ]
)
