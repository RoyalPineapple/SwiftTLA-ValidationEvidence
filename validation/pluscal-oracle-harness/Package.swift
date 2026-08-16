// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PlusCalOracleHarness",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../SwiftTLA")],
    targets: [
        .executableTarget(
            name: "pluscal-oracle-harness",
            dependencies: [.product(name: "AlgorithmConformance", package: "SwiftTLA")]
        )
    ]
)
