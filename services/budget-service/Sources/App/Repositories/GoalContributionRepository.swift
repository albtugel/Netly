import Foundation
import Logging
import PostgresNIO

/// Data access for goal contributions. Every method is scoped to the goal's owner: another user's goal behaves as missing.
protocol GoalContributionRepository: Sendable {
    /// Records a contribution and adds its amount to the goal's `savedAmount`, both or neither.
    /// Returns `nil` when the goal does not exist for this user. Throws `GoalTargetExceededError`
    /// when the new `savedAmount` would pass `targetAmount`; then no contribution is recorded either.
    func contribute(goalID: UUID, userID: UUID, amount: Decimal, note: String?) async throws -> (contribution: GoalContribution, goal: Record<GoalFields>)?
    /// Contributions of the goal, oldest first, with the total count before paging; `nil` when the goal does not exist for this user.
    func list(goalID: UUID, userID: UUID, limit: Int, offset: Int) async throws -> (records: [GoalContribution], total: Int)?
}

struct GoalTargetExceededError: Error {}

struct PostgresGoalContributionRepository: GoalContributionRepository {
    static let savedWithinTargetConstraint = "goals_saved_within_target"

    let client: PostgresClient
    let logger: Logger

    func contribute(goalID: UUID, userID: UUID, amount: Decimal, note: String?) async throws -> (contribution: GoalContribution, goal: Record<GoalFields>)? {
        do {
            return try await client.withTransaction(logger: logger) { connection in
                // Step 1: the contribution. INSERT … SELECT inserts nothing when the goal is not this user's.
                let inserted = try await connection.query(
                    """
                    INSERT INTO goal_contributions (id, goal_id, amount, note)
                    SELECT \(UUID()), id, \(amount), \(note) FROM goals WHERE id = \(goalID) AND user_id = \(userID)
                    RETURNING id, goal_id, amount, note, created_at
                    """,
                    logger: logger
                ).collect()
                guard let row = inserted.first else { return nil }
                let contribution = try GoalContribution(cells: row.makeRandomAccess())

                // Step 2: the goal's running total. Passing the target breaks CHECK goals_saved_within_target here,
                // and the transaction rolls step 1 back with it. The check runs in the database, not as a read
                // before the write, so two concurrent contributions cannot both pass it.
                let updated = try await connection.query(
                    """
                    UPDATE goals SET saved_amount = saved_amount + \(amount), updated_at = now()
                    WHERE id = \(goalID)
                    RETURNING \(unescaped: GoalRepository.selectList)
                    """,
                    logger: logger
                ).collect()
                guard let goalRow = updated.first else {
                    throw PostgresRepositoryError.missingReturnedRow(table: "goals")
                }
                return (contribution, try Record<GoalFields>(cells: goalRow.makeRandomAccess()))
            }
        } catch let error as PostgresTransactionError {
            if let failure = error.closureError as? PSQLError,
               failure.serverInfo?[.constraintName] == Self.savedWithinTargetConstraint {
                throw GoalTargetExceededError()
            }
            throw error
        }
    }

    func list(goalID: UUID, userID: UUID, limit: Int, offset: Int) async throws -> (records: [GoalContribution], total: Int)? {
        let owned = try await client.query("SELECT 1 FROM goals WHERE id = \(goalID) AND user_id = \(userID)", logger: logger).collect()
        guard !owned.isEmpty else { return nil }

        var total = 0
        let counts = try await client.query("SELECT COUNT(*) FROM goal_contributions WHERE goal_id = \(goalID)", logger: logger)
        for try await count in counts.decode(Int.self) {
            total = count
        }

        let rows = try await client.query(
            """
            SELECT id, goal_id, amount, note, created_at FROM goal_contributions
            WHERE goal_id = \(goalID) ORDER BY created_at, id LIMIT \(limit) OFFSET \(offset)
            """,
            logger: logger
        )
        var records: [GoalContribution] = []
        for try await row in rows {
            records.append(try GoalContribution(cells: row.makeRandomAccess()))
        }
        return (records, total)
    }
}

extension GoalContribution {
    init(cells: PostgresRandomAccessRow) throws {
        self.init(
            id: try cells["id"].decode(UUID.self),
            goalID: try cells["goal_id"].decode(UUID.self),
            amount: try cells["amount"].decode(Decimal.self),
            note: try cells["note"].decode(String?.self),
            createdAt: try cells["created_at"].decode(Date.self)
        )
    }
}

/// Process-local contributions for tests. It updates goals through the in-memory goal repository and is not atomic.
actor InMemoryGoalContributionRepository: GoalContributionRepository {
    private let goals: InMemoryRecordRepository<GoalFields>
    private let clock: @Sendable () -> Date
    private var contributions: [GoalContribution] = []

    init(goals: InMemoryRecordRepository<GoalFields>, clock: @escaping @Sendable () -> Date) {
        self.goals = goals
        self.clock = clock
    }

    func contribute(goalID: UUID, userID: UUID, amount: Decimal, note: String?) async throws -> (contribution: GoalContribution, goal: Record<GoalFields>)? {
        guard var fields = await goals.find(id: goalID, userID: userID)?.fields else { return nil }
        fields.savedAmount += amount
        guard fields.savedAmount <= fields.targetAmount else { throw GoalTargetExceededError() }
        guard let goal = await goals.update(id: goalID, userID: userID, fields: fields) else { return nil }

        let contribution = GoalContribution(id: UUID(), goalID: goalID, amount: amount, note: note, createdAt: clock())
        contributions.append(contribution)
        return (contribution, goal)
    }

    func list(goalID: UUID, userID: UUID, limit: Int, offset: Int) async throws -> (records: [GoalContribution], total: Int)? {
        guard await goals.find(id: goalID, userID: userID) != nil else { return nil }
        let matching = contributions.filter { $0.goalID == goalID }
        return (Array(matching.dropFirst(offset).prefix(limit)), matching.count)
    }
}
