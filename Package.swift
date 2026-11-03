// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HavaliDuvar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "HavaliDuvar", path: "Sources/HavaliDuvar")
    ]
)
