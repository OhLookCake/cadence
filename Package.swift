// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Cadence",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Cadence", targets: ["Cadence"]),
               .executable(name: "CadenceRunner", targets: ["CadenceRunner"])],
    targets: [.target(name: "CadenceCore"),
              .executableTarget(name: "Cadence", dependencies: ["CadenceCore"]),
              .executableTarget(name: "CadenceRunner", dependencies: ["CadenceCore"]),
              .executableTarget(name: "CadenceChecks", dependencies: ["CadenceCore"], path: "Tests/CadenceCoreTests")]
)
