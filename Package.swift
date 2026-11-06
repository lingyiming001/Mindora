// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mindora",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Mindora", targets: ["Mindora"])],
    dependencies: [.package(path: "Vendor/KokoroRuntime")],
    targets: [
        .executableTarget(name: "Mindora", dependencies: [
            .product(name: "MindoraKokoroRuntime", package: "KokoroRuntime")
        ], path: "Sources/Mindora"),
        .testTarget(name: "MindoraTests", dependencies: ["Mindora"])
    ]
)
