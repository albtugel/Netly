import Foundation
import Logging
import PostgresNIO

extension PostgresClient.Configuration {
    static let requiredEnvironmentVariables = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"]

    /// Reads the connection from `DB_HOST`, `DB_PORT` (default 5432), `DB_NAME`, `DB_USER` and `DB_PASSWORD`.
    /// `DB_SSLMODE=require` forces TLS; otherwise the connection is plain, as on the internal compose network.
    static func fromEnvironment(_ environment: [String: String]) throws -> Self {
        let missing = requiredEnvironmentVariables.filter { environment[$0]?.isEmpty ?? true }
        guard missing.isEmpty else {
            throw AppConfiguration.InvalidConfiguration(description: "Database settings are missing: \(missing.joined(separator: ", "))")
        }

        var port = 5432
        if let rawPort = environment["DB_PORT"], !rawPort.isEmpty {
            guard let parsed = Int(rawPort), (1...65535).contains(parsed) else {
                throw AppConfiguration.InvalidConfiguration(description: "DB_PORT must be a port number, got \(rawPort)")
            }
            port = parsed
        }

        return Self(
            host: environment["DB_HOST"]!,
            port: port,
            username: environment["DB_USER"]!,
            password: environment["DB_PASSWORD"]!,
            database: environment["DB_NAME"]!,
            tls: environment["DB_SSLMODE"] == "require" ? .require(.makeClientConfiguration()) : .disable
        )
    }
}

extension PostgresClient {
    /// Runs a trivial query so a wrong host or password stops start-up instead of failing the first request,
    /// and logs which server and database the service reached.
    func logConnection(to configuration: Configuration, logger: Logger) async throws {
        let rows = try await query(
            "SELECT current_database(), current_user, current_setting('server_version')",
            logger: logger
        )
        for try await (database, user, version) in rows.decode((String, String, String).self) {
            let address = "\(configuration.host ?? "unix socket"):\(configuration.port ?? 5432)"
            logger.info("Connected to PostgreSQL \(version) at \(address), database \(database) as \(user)")
        }
    }
}
