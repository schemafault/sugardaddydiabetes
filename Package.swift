// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiabetesMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DiabetesMonitor",
            targets: ["DiabetesMonitor"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DiabetesMonitor",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("../Info.plist"),
                .copy("Models/CoreData/DiabetesData.xcdatamodeld")
            ]
        )
    ]
) 