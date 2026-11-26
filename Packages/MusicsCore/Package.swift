// swift-tools-version:5.9
// Platform-independent core of Musics: models, server providers, endpoint resolution,
// queue engine, search. Builds and tests on Linux as well as iOS, so the logic can be
// checked without Xcode.
import PackageDescription

let package = Package(
    name: "MusicsCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MusicsCore", targets: ["MusicsCore"]),
    ],
    targets: [
        .target(name: "MusicsCore"),
        .testTarget(name: "MusicsCoreTests", dependencies: ["MusicsCore"]),
    ]
)
