// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "FlowCore", platforms: [.iOS(.v16), .macOS(.v12)], products: [.library(name: "FlowCore", targets: ["FlowCore"])], targets: [.target(name: "FlowCore"), .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"])])
