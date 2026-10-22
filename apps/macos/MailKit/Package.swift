// swift-tools-version: 6.2
import PackageDescription

// Everything below the views lives here, shared by the Mac and iPhone apps, so it builds and tests with `swift test`
// without either app target.
let package = Package(
    name: "MailKit",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "MailCore", targets: ["MailCore"]),
        .library(name: "Providers", targets: ["Providers"]),
        .library(name: "Assist", targets: ["Assist"]),
        .library(name: "MailUI", targets: ["MailUI"]),
        .library(name: "Agents", targets: ["Agents"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [.process("Fonts")]
        ),
        .target(
            name: "MailCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .target(
            name: "APIClient",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .target(
            name: "Providers",
            dependencies: [
                "MailCore",
                "APIClient",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
        .target(
            name: "Assist",
            dependencies: ["MailCore"]
        ),
        .target(
            name: "MailUI",
            dependencies: [
                "DesignSystem",
                "MailCore",
                "Assist",
                "Providers",
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .target(
            name: "Agents",
            dependencies: [
                "MailCore",
                "MailUI",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .testTarget(name: "MailCoreTests", dependencies: ["MailCore"]),
        .testTarget(name: "MailUITests", dependencies: ["MailUI", "MailCore"]),
        .testTarget(name: "AssistTests", dependencies: ["Assist", "MailCore"]),
        .testTarget(
            name: "AgentsTests",
            dependencies: ["Agents", "MailCore", "MailUI", .product(name: "MCP", package: "swift-sdk")]
        ),
        .testTarget(
            name: "ProvidersTests",
            dependencies: [
                "Providers",
                "MailCore",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
