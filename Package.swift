// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AjazzDeck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AjazzKit", targets: ["AjazzKit"]),
        .executable(name: "ajazzctl", targets: ["ajazzctl"]),
        .executable(name: "ajazzdeck", targets: ["ajazzdeck"]),
    ],
    targets: [
        .target(name: "AjazzKit"),
        .executableTarget(name: "ajazzctl", dependencies: ["AjazzKit"]),
        .executableTarget(name: "ajazzdeck", dependencies: ["AjazzKit"]),
        .testTarget(name: "AjazzKitTests", dependencies: ["AjazzKit"]),
    ]
)
