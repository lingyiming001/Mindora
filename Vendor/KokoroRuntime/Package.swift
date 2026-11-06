// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MindoraKokoroRuntime",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MindoraKokoroRuntime", type: .static, targets: ["MindoraKokoroRuntime"])],
    targets: [
        .binaryTarget(
            name: "SherpaOnnxMacOS",
            url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-macos-static.xcframework.zip",
            checksum: "93f7a064abe99e0d6185a88c5b36ce18c4bff35cd0d5e4e81f81151de8e3e7e5"
        ),
        .binaryTarget(
            name: "OnnxruntimeMacOS",
            url: "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.2/onnxruntime-macos-static-xcframework-1.28.2.xcframework.zip",
            checksum: "cb0b0bec912c77229517c463e28a3fac9674c521f9599919efff1ef2b42f3da0"
        ),
        .target(
            name: "MindoraKokoroRuntime",
            dependencies: ["SherpaOnnxMacOS", "OnnxruntimeMacOS"],
            path: "Sources",
            linkerSettings: [.linkedLibrary("c++"), .linkedFramework("CoreML"), .linkedFramework("Accelerate")]
        )
    ]
)
