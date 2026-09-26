import Foundation

struct AppConfiguration: Sendable {
    static let developmentJWTSecret = "netly-dev-jwt-secret-change-me-32bytes"
    /// HS256 needs a key at least as long as its 32-byte digest.
    static let minimumJWTSecretLength = 32

    var hostname: String
    var port: Int
    var jwtSecret: String

    struct InvalidConfiguration: Error, CustomStringConvertible {
        let description: String
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppConfiguration {
        let configuration = AppConfiguration(
            hostname: "0.0.0.0",
            port: environment["PORT"].flatMap(Int.init) ?? 8082,
            jwtSecret: environment["JWT_SECRET"] ?? developmentJWTSecret
        )
        guard configuration.jwtSecret.utf8.count >= minimumJWTSecretLength else {
            throw InvalidConfiguration(description: "JWT_SECRET must be at least \(minimumJWTSecretLength) bytes long")
        }
        return configuration
    }
}
