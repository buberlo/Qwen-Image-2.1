// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "QwenCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "QwenCore", targets: ["QwenCore"])],
    targets: [
        .target(name: "QwenCore", path: "App/Core")
    ],
    swiftLanguageModes: [.v5]
)
