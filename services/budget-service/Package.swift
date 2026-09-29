// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "budget-service",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "PostgresNIO", package: "postgres-nio")
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                "App",
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ]
        )
    ]
)
