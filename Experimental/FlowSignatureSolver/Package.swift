// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FlowSignatureSolver",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "FlowSignatureSolver", targets: ["FlowSignatureSolver"])],
    targets: [
        .target(name: "FlowSignatureSolver", resources: [.process("Resources")]),
        .testTarget(name: "FlowSignatureSolverTests", dependencies: ["FlowSignatureSolver"])
    ]
)
