// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComputexHost",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ComputexHost", targets: ["ComputexHost"])
    ],
    targets: [
        .executableTarget(
            name: "ComputexHost",
            path: "Sources/ComputexHost",
            linkerSettings: [
                .linkedFramework("Virtualization"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "ComputexHostTests",
            dependencies: ["ComputexHost"],
            path: "Tests/ComputexHostTests"
        )
    ]
)
