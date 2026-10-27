// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CZlib",
    products: [.library(name: "CZlib", targets: ["CZlib"])],
    targets: [
        .systemLibrary(name: "CZlib", path: "Sources/CZlib", providers: [.brew(["zlib"])])
    ]
)
