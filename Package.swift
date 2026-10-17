// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LayoutSnap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LayoutSnap", targets: ["LayoutSnap"])
    ],
    targets: [
        .executableTarget(
            name: "LayoutSnap",
            path: "Sources/LayoutSnap"
        )
    ]
)
