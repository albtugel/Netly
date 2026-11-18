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

    /// A day is far beyond any useful TTL; the bound also keeps the value safely convertible and addable to a date.
    static let maximumSummaryCacheTTL = 86_400

    /// `SUMMARY_CACHE_TTL_SECONDS`: a whole number of seconds, `0` to disable, at most a day; default 60.
    private static func summaryCacheTTL(_ raw: String?) throws -> TimeInterval {
        guard let raw, !raw.isEmpty else { return SummaryCache.defaultTTL }
        guard let seconds = Int(raw), (0...maximumSummaryCacheTTL).contains(seconds) else {
            throw InvalidConfiguration(description: "SUMMARY_CACHE_TTL_SECONDS must be a whole number from 0 to \(maximumSummaryCacheTTL), got \(raw)")
        }
        return TimeInterval(seconds)
    }
}
