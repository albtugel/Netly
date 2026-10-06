import Logging
import PostgresMigrations
import PostgresNIO

/// Creates every table with its keys and constraints, plus the indexes behind the default list order.
/// CHECK constraints repeat the API rules so the database stays consistent even if a bug slips past validation.
struct CreateBudgetSchema: DatabaseMigration {
    let name = "001_create_budget_schema"

    func apply(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.run(
            [
                """
                CREATE TABLE subscriptions (
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
                // The same subscription entered twice would double its cost in the monthly budget.
                "CREATE UNIQUE INDEX subscriptions_user_name_key ON subscriptions (user_id, lower(name))",
                "CREATE INDEX subscriptions_user_created_idx ON subscriptions (user_id, created_at, id)",
                """
                CREATE TABLE debts (
                    id UUID PRIMARY KEY,
                    user_id UUID NOT NULL,
                    creditor TEXT NOT NULL CHECK (char_length(creditor) BETWEEN 1 AND 100),
                    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
                    due_date DATE NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """,
                "CREATE INDEX debts_user_created_idx ON debts (user_id, created_at, id)",
                """
                CREATE TABLE goals (
                    id UUID PRIMARY KEY,
                    user_id UUID NOT NULL,
                    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
                    target_amount NUMERIC(12, 2) NOT NULL CHECK (target_amount > 0),
                    saved_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (saved_amount >= 0),
                    target_date DATE NOT NULL,
                    priority INTEGER NOT NULL CHECK (priority BETWEEN 1 AND 10),
                    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                    CONSTRAINT goals_saved_within_target CHECK (saved_amount <= target_amount)
                )
                """,
                "CREATE INDEX goals_user_created_idx ON goals (user_id, created_at, id)",
                """
                CREATE TABLE goal_contributions (
                    id UUID PRIMARY KEY,
                    goal_id UUID NOT NULL REFERENCES goals (id) ON DELETE CASCADE,
                    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
                    note TEXT CHECK (char_length(note) <= 200),
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """,
                // PostgreSQL does not index foreign keys on its own; this one serves the per-goal list and the cascade.
                "CREATE INDEX goal_contributions_goal_created_idx ON goal_contributions (goal_id, created_at, id)",
            ],
            logger: logger
        )
    }

    func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.run(
            ["DROP TABLE goal_contributions", "DROP TABLE goals", "DROP TABLE debts", "DROP TABLE subscriptions"],
            logger: logger
        )
    }
}

extension PostgresConnection {
    /// Runs schema statements one by one. They come from migration source code, never from input.
    func run(_ statements: [String], logger: Logger) async throws {
        for statement in statements {
            try await query(PostgresQuery(unsafeSQL: statement), logger: logger)
        }
    }
}
