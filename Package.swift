// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ProductLabels", platforms: [.iOS(.v17), .macOS(.v14)], targets: [
    .target(name: "LabelCore", path: "Sources/LabelCore"),
    .testTarget(name: "LabelCoreTests", dependencies: ["LabelCore"], path: "Tests/LabelCoreTests")
])
