import Foundation
import PostgresNIO

struct AppConfiguration: Sendable {
    static let developmentJWTSecret = "netly-dev-jwt-secret-change-me-32bytes"
    /// HS256 needs a key at least as long as its 32-byte digest.
    static let minimumJWTSecretLength = 32

    var hostname: String
    var port: Int
    var jwtSecret: String
    var database: PostgresClient.Configuration
    /// How long `GET /api/v1/summary` may be served from the cache; zero turns the cache off.
    var summaryCacheTTL: TimeInterval = SummaryCache.defaultTTL

    struct InvalidConfiguration: Error, CustomStringConvertible {
        let description: String
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppConfiguration {
        let configuration = AppConfiguration(
            hostname: "0.0.0.0",
            port: environment["PORT"].flatMap(Int.init) ?? 8082,
            jwtSecret: environment["JWT_SECRET"] ?? developmentJWTSecret,
            database: try .fromEnvironment(environment),
            summaryCacheTTL: try summaryCacheTTL(environment["SUMMARY_CACHE_TTL_SECONDS"])
        )
        guard configuration.jwtSecret.utf8.count >= minimumJWTSecretLength else {
            throw InvalidConfiguration(description: "JWT_SECRET must be at least \(minimumJWTSecretLength) bytes long")
        }
        return configuration
    }

    /// `SUMMARY_CACHE_TTL_SECONDS`: a whole number of seconds, `0` to disable; default 60.
    private static func summaryCacheTTL(_ raw: String?) throws -> TimeInterval {
        guard let raw, !raw.isEmpty else { return SummaryCache.defaultTTL }
        guard let seconds = Int(raw), seconds >= 0 else {
            throw InvalidConfiguration(description: "SUMMARY_CACHE_TTL_SECONDS must be a non-negative whole number, got \(raw)")
        }
        return TimeInterval(seconds)
    }
}
