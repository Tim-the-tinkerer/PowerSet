// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PowerSet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PowerSet", targets: ["PowerSet"]),
    ],
    targets: [
        .executableTarget(
            name: "PowerSet",
            path: "Sources/PowerSet"
        ),
    ]
)
