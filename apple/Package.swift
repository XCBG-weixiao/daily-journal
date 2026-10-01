// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DailyJournalApple",
    platforms: [.macOS("15.0"), .iOS("18.0")],
    products: [.library(name: "ProbeCore", targets: ["ProbeCore"]),
               .library(name: "JournalCore", targets: ["JournalCore"]),
               .executable(name: "DailyJournalProbe", targets: ["ProbeApp"]),
               .executable(name: "DailyJournal", targets: ["JournalMac"]),
               .executable(name: "JournalChecks", targets: ["JournalChecks"])],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", exact: "2.4.1")
    ],
    targets: [
        .target(name: "ProbeCore"),
        .executableTarget(name: "ProbeApp", dependencies: ["ProbeCore"]),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"]),
        .target(name: "JournalCore", dependencies: ["Yams"]),
        .executableTarget(name: "JournalMac", dependencies: ["JournalCore", .product(name: "MarkdownUI", package: "swift-markdown-ui")]),
        .executableTarget(name: "JournalChecks", dependencies: ["JournalCore"], path: "Checks")
    ]
)
