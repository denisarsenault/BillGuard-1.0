// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BillGuardCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BillGuardCore", targets: ["BillGuardCore"])
    ],
    targets: [
        .target(name: "BillGuardCore", resources: [.process("Resources")]),
        .testTarget(name: "BillGuardCoreTests", dependencies: ["BillGuardCore"])
    ]
)
