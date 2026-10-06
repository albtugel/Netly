import Foundation
import Logging
import PostgresNIO

/// `App` or `App serve` starts the HTTP server, `App migrate` applies pending migrations,
/// `App rollback` reverts the newest one.
@main
struct App {
    static func main() async {
        do {
            try await run(command: CommandLine.arguments.dropFirst().first)
        } catch {
            makeLogger().critical("\(error)")
            exit(1)
        }
    }

    private static func run(command: String?) async throws {
        let configuration = try AppConfiguration.fromEnvironment()
        switch command {
        case nil, "serve":
            let app = try await buildApplication(configuration: configuration)
            try await app.runService()
        case "migrate":
            try await withPostgresClient(configuration.database) { client, logger in
                try await BudgetMigrations.apply(client: client, logger: logger)
            }
        case "rollback":
            try await withPostgresClient(configuration.database) { client, logger in
                try await BudgetMigrations.revertLatest(client: client, logger: logger)
            }
        case let command?:
            throw AppConfiguration.InvalidConfiguration(description: "Unknown command \(command); expected serve, migrate or rollback")
        }
    }

    /// Runs a one-off command against the database without starting the HTTP server.
    private static func withPostgresClient(
        _ configuration: PostgresClient.Configuration,
        _ body: @Sendable (PostgresClient, Logger) async throws -> Void
    ) async throws {
        let logger = makeLogger()
        let client = PostgresClient(configuration: configuration, backgroundLogger: logger)
        let running = Task { await client.run() }
        defer { running.cancel() }
        // Let `run()` start first; a query issued before it only waits, but logs a warning.
        try await Task.sleep(for: .milliseconds(10))
        try await client.logConnection(to: configuration, logger: logger)
        try await body(client, logger)
    }
}
