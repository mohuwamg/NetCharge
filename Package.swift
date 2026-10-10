// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetCharge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NetCharge", targets: ["NetCharge"]),
        .executable(name: "netcharge-helper", targets: ["NetChargeHelper"])
    ],
    targets: [
        .target(name: "NetChargeCore"),
        .executableTarget(name: "NetCharge", dependencies: ["NetChargeCore"]),
        .executableTarget(name: "NetChargeHelper", dependencies: ["NetChargeCore"]),
        .testTarget(name: "NetChargeCoreTests", dependencies: ["NetChargeCore"])
    ]
)
