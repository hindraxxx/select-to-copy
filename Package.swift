// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SelectToCopy",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "SelectToCopy", targets: ["SelectToCopy"])
    ],
    targets: [
        .executableTarget(
            name: "SelectToCopy",
            dependencies: [],
            exclude: [
                "Resources/Info.plist"
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/SelectToCopy/Resources/Info.plist"
                ])
            ]
        )
    ]
)
