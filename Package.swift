// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ToDoModule",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ToDoModule", targets: ["ToDoModule"])
    ],
    targets: [
        .target(
            name: "ToDoCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ToDoModule",
            dependencies: ["ToDoCore"]
        ),
        .testTarget(
            name: "ToDoCoreTests",
            dependencies: ["ToDoCore"]
        )
    ]
)
