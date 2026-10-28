import Fluent
import SQLKit

/// The `users` table. Written in SQL rather than the Fluent schema builder to keep the CHECK constraints,
/// which repeat the API rules so the database stays consistent even if a bug slips past validation.
struct CreateUsers: AsyncMigration {
    var name: String { "001_create_users" }

    func prepare(on database: any Database) async throws {
        let sql = database as! any SQLDatabase
        try await sql.raw("""
            CREATE TABLE users (
                id UUID PRIMARY KEY,
                email TEXT NOT NULL CHECK (char_length(email) BETWEEN 3 AND 254 AND email = lower(email)),
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
                created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                -- One account per address; the index behind it also serves the lookup on every login.
                CONSTRAINT users_email_key UNIQUE (email)
            )
            """).run()
    }

    func revert(on database: any Database) async throws {
        try await (database as! any SQLDatabase).raw("DROP TABLE users").run()
    }
}
