// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Orion",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "Orion", path: "Sources/Orion",
                          resources: [.process("Resources")]),
        .testTarget(name: "OrionTests", dependencies: ["Orion"], path: "Tests/OrionTests"),
    ]
)
