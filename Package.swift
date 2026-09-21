// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "AstraBar", platforms: [.macOS(.v13)],
    products: [.executable(name: "AstraBar", targets: ["AstraBar"]), .executable(name: "astra-usage", targets: ["AstraUsage"]), .library(name: "UsageCore", targets: ["UsageCore"])],
    targets: [.target(name: "UsageCore"), .executableTarget(name: "AstraBar", dependencies: ["UsageCore"]), .executableTarget(name: "AstraUsage", dependencies: ["UsageCore"]), .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])]
)
