import Logging
import PostgresMigrations
import PostgresNIO

/// The schema history, oldest first. Append new migrations; never edit or reorder ones that may have been applied.
enum BudgetMigrations {
    static let all: [any DatabaseMigration] = [
        CreateBudgetSchema(),
        AddGoalStatusIndex(),
    ]

    /// Applies every migration the database has not seen yet, all in one transaction.
    static func apply(client: PostgresClient, logger: Logger) async throws {
        let migrations = DatabaseMigrations()
        await migrations.add(contentsOf: all)
        try await migrations.apply(client: client, logger: logger, dryRun: false)
        logger.info("Database schema is up to date")
    }

    /// Reverts the newest migration if it is applied.
    static func revertLatest(client: PostgresClient, logger: Logger) async throws {
        // `revertInconsistent` reverts applied migrations that are missing from the list,
        // so the newest one is only registered, not added.
        let migrations = DatabaseMigrations()
        await migrations.add(contentsOf: all.dropLast())
        await migrations.register(all[all.count - 1])
        try await migrations.revertInconsistent(client: client, logger: logger, dryRun: false)
        logger.info("Database schema is at \(all[all.count - 2].name)")
    }

    /// Stops start-up when the database is behind the code instead of serving requests against an old schema.
    static func verify(client: PostgresClient, logger: Logger) async throws {
        let migrations = DatabaseMigrations()
        await migrations.add(contentsOf: all)
        do {
            try await migrations.apply(client: client, logger: logger, dryRun: true)
        } catch let error as DatabaseMigrationError where error == .requiresChanges {
            throw AppConfiguration.InvalidConfiguration(description: "Database schema is out of date; run `App migrate` first")
        }
    }
}
