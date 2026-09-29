import Logging
import PostgresNIO

/// Idempotent schema setup, run before the server accepts requests.
/// CHECK constraints repeat the API rules so the database stays consistent even if a bug slips past validation.
enum Schema {
    static let statements: [String] = [
        """
        CREATE TABLE IF NOT EXISTS subscriptions (
            id UUID PRIMARY KEY,
            user_id UUID NOT NULL,
            name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
            price NUMERIC(12, 2) NOT NULL CHECK (price > 0),
            billing_cycle TEXT NOT NULL CHECK (billing_cycle IN ('weekly', 'monthly', 'quarterly', 'yearly')),
            next_charge_date DATE NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """,
        "CREATE INDEX IF NOT EXISTS subscriptions_user_created_idx ON subscriptions (user_id, created_at, id)",
        """
        CREATE TABLE IF NOT EXISTS debts (
            id UUID PRIMARY KEY,
            user_id UUID NOT NULL,
            creditor TEXT NOT NULL CHECK (char_length(creditor) BETWEEN 1 AND 100),
            amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
            due_date DATE NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """,
        "CREATE INDEX IF NOT EXISTS debts_user_created_idx ON debts (user_id, created_at, id)",
        """
        CREATE TABLE IF NOT EXISTS goals (
            id UUID PRIMARY KEY,
            user_id UUID NOT NULL,
            name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
            target_amount NUMERIC(12, 2) NOT NULL CHECK (target_amount > 0),
            saved_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (saved_amount >= 0 AND saved_amount <= target_amount),
            target_date DATE NOT NULL,
            priority INTEGER NOT NULL CHECK (priority BETWEEN 1 AND 10),
            status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
        """,
        "CREATE INDEX IF NOT EXISTS goals_user_created_idx ON goals (user_id, created_at, id)",
    ]

    static func migrate(client: PostgresClient, logger: Logger) async throws {
        try await client.withTransaction(logger: logger) { connection in
            for statement in statements {
                try await connection.query(PostgresQuery(unsafeSQL: statement), logger: logger)
            }
        }
        logger.info("Database schema is up to date")
    }
}
