import Foundation
import PostgresNIO

extension PostgresClient.Configuration {
    /// Builds a configuration from `postgres://user:password@host:port/database`.
    /// Add `?sslmode=require` to force TLS; otherwise the connection is plain, as on the internal compose network.
    init(databaseURL: String) throws {
        guard let components = URLComponents(string: databaseURL),
              ["postgres", "postgresql"].contains(components.scheme),
              let host = components.host, !host.isEmpty,
              let username = components.user
        else {
            throw AppConfiguration.InvalidConfiguration(description: "DATABASE_URL must look like postgres://user:password@host:port/database")
        }

        let database = components.path.split(separator: "/").first.map(String.init)
        let requiresTLS = components.queryItems?.contains { $0.name == "sslmode" && $0.value == "require" } ?? false
        self.init(
            host: host,
            port: components.port ?? 5432,
            username: username.removingPercentEncoding ?? username,
            password: components.password?.removingPercentEncoding,
            database: database,
            tls: requiresTLS ? .require(.makeClientConfiguration()) : .disable
        )
    }
}
