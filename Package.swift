// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mindora",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Mindora", targets: ["Mindora"])],
    targets: [
        .executableTarget(name: "Mindora", path: "Sources/Mindora"),
        .testTarget(name: "MindoraTests", dependencies: ["Mindora"])
    ]
)
