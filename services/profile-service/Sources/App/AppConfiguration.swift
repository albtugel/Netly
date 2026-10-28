import FluentPostgresDriver
import Foundation
import NIOSSL

struct AppConfiguration: Sendable {
    static let developmentJWTSecret = "netly-dev-jwt-secret-change-me-32bytes"
    /// HS256 needs a key at least as long as its 32-byte digest.
    static let minimumJWTSecretLength = 32
    static let requiredDatabaseVariables = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"]

    var port: Int
    var jwtSecret: String
    var database: SQLPostgresConfiguration

    struct InvalidConfiguration: Error, CustomStringConvertible {
        let description: String
    }

    /// Reads `PORT`, `JWT_SECRET` and the `DB_*` variables, the same names Budget Service uses.
    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppConfiguration {
        let missing = requiredDatabaseVariables.filter { environment[$0]?.isEmpty ?? true }
        guard missing.isEmpty else {
            throw InvalidConfiguration(description: "Database settings are missing: \(missing.joined(separator: ", "))")
        }
        var databasePort = 5432
        if let rawPort = environment["DB_PORT"], !rawPort.isEmpty {
            guard let parsed = Int(rawPort), (1...65535).contains(parsed) else {
                throw InvalidConfiguration(description: "DB_PORT must be a port number, got \(rawPort)")
            }
            databasePort = parsed
        }

        let jwtSecret = environment["JWT_SECRET"] ?? developmentJWTSecret
        guard jwtSecret.utf8.count >= minimumJWTSecretLength else {
            throw InvalidConfiguration(description: "JWT_SECRET must be at least \(minimumJWTSecretLength) bytes long")
        }

        return AppConfiguration(
            port: environment["PORT"].flatMap(Int.init) ?? 8081,
            jwtSecret: jwtSecret,
            database: SQLPostgresConfiguration(
                hostname: environment["DB_HOST"]!,
                port: databasePort,
                username: environment["DB_USER"]!,
                password: environment["DB_PASSWORD"]!,
                database: environment["DB_NAME"]!,
                tls: environment["DB_SSLMODE"] == "require"
                    ? .require(try NIOSSLContext(configuration: .makeClientConfiguration()))
                    : .disable
            )
        )
    }
}
