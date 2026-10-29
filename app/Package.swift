// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Orion",
    platforms: [.macOS(.v12)],
    dependencies: [
        // App updates (Beat Key › Check for Updates…, Run Doctor). Pinned: build.sh embeds and
        // re-signs this exact framework, and uses its bin/ tools for the appcast.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(name: "Orion",
                          dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/Orion",
                          resources: [.process("Resources")],
                          // build.sh puts Sparkle.framework in Contents/Frameworks
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath",
                                                         "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "OrionTests", dependencies: ["Orion"], path: "Tests/OrionTests"),
    ]
)
