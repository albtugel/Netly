import Logging
import PostgresMigrations
import PostgresNIO

/// Index for the most frequent goal query, `GET /goals?status=active`: the goals screen opens on active goals,
/// and the free balance is distributed among the same set.
///
/// The query is `WHERE user_id = $1 AND status = $2 ORDER BY created_at, id LIMIT … OFFSET …`. This index covers
/// the filter and the order together, so PostgreSQL reads one page straight from it without sorting. The index on
/// `user_id` alone would make it read every goal of the user, completed and archived ones included, which over
/// time become the majority.
struct AddGoalStatusIndex: DatabaseMigration {
    let name = "002_add_goal_status_index"

    func apply(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.run(["CREATE INDEX goals_user_status_idx ON goals (user_id, status, created_at, id)"], logger: logger)
    }

    func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.run(["DROP INDEX goals_user_status_idx"], logger: logger)
    }
}
