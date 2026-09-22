// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OpenReaderCore", platforms: [.macOS(.v14)], products: [.library(name: "OpenReaderCore", targets: ["OpenReaderCore"])], targets: [.target(name: "OpenReaderCore", path: "Core"), .testTarget(name: "OpenReaderCoreTests", dependencies: ["OpenReaderCore"], path: "Tests")])
