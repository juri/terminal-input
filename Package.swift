// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "terminal-input",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "TerminalInput",
            targets: ["TerminalInput"]
        ),
        .executable(
            name: "run-terminal-input",
            targets: ["TerminalInputRunner"]
        ),
    ],
    targets: [
        .target(
            name: "TerminalInput"
        ),
        .executableTarget(
            name: "TerminalInputRunner",
            dependencies: ["TerminalInput"],
        ),
        .testTarget(
            name: "TerminalInputTests",
            dependencies: ["TerminalInput"]
        ),
    ]
)
