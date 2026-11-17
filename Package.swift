// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PokeTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PokeTokenBar",
            path: "Sources/PokeTokenBar",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PokeTokenBarTests",
            dependencies: ["PokeTokenBar"],
            path: "Tests/PokeTokenBarTests",
            exclude: ["Fixtures/evolution-steps.json", "Fixtures/kanto-gym-catalog.json"],
            resources: [
                .copy("Fixtures/CodexFork"),
                .copy("Fixtures/CodexSubagent"),
            ]
        ),
    ]
)
