// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CAPMKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CAPMKit", targets: ["CAPMKit"])],
    targets: [
        .target(name: "CAPMKit", resources: [.process("Localizable.xcstrings")]),
        .testTarget(name: "CAPMKitTests", dependencies: ["CAPMKit"], resources: [.copy("Fixtures")]),
    ]
)
