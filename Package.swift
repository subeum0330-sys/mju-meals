// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyongjiMeals",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MealCore", targets: ["MealCore"]),
        .executable(name: "MyongjiMealsPreview", targets: ["MyongjiMealsApp"])
    ],
    targets: [
        .target(name: "MealCore", resources: [.process("Resources")]),
        .executableTarget(name: "MyongjiMealsApp", dependencies: ["MealCore"]),
        .testTarget(
            name: "MealCoreTests",
            dependencies: ["MealCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
