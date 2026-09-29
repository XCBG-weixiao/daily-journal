// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DailyJournalApple",
    platforms: [.macOS("15.0"), .iOS("18.0")],
    products: [.library(name: "ProbeCore", targets: ["ProbeCore"]),
               .executable(name: "DailyJournalProbe", targets: ["ProbeApp"])],
    targets: [
        .target(name: "ProbeCore"),
        .executableTarget(name: "ProbeApp", dependencies: ["ProbeCore"]),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"])
    ]
)
