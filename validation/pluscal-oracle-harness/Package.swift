// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlusCalOracleHarness",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../SwiftTLA")],
    targets: [
        .target(
            name: "SwiftTLAValidationFixtures",
            dependencies: [
                .product(name: "SwiftTLA", package: "SwiftTLA"),
                .product(name: "SwiftTLAMacros", package: "SwiftTLA"),
                .product(name: "UpstreamParity", package: "SwiftTLA")
            ]
        ),
        .executableTarget(
            name: "pluscal-oracle-harness",
            dependencies: ["SwiftTLAValidationFixtures"]
        )
    ]
)
