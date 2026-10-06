import Foundation
import Logging
import PostgresNIO

/// Storage for every resource the service exposes.
struct Repositories: Sendable {
    var subscriptions: any RecordRepository<SubscriptionFields>
    var debts: any RecordRepository<DebtFields>
    var goals: any RecordRepository<GoalFields>
    var goalContributions: any GoalContributionRepository

    static func inMemory(clock: @escaping @Sendable () -> Date = { Date() }) -> Repositories {
        let goals = InMemoryRecordRepository<GoalFields>(clock: clock)
        return Repositories(
            subscriptions: InMemoryRecordRepository(clock: clock),
            debts: InMemoryRecordRepository(clock: clock),
            goals: goals,
            goalContributions: InMemoryGoalContributionRepository(goals: goals, clock: clock)
        )
    }
}

extension Repositories {
    static func postgres(client: PostgresClient, logger: Logger) -> Repositories {
        Repositories(
            subscriptions: SubscriptionRepository(client: client, logger: logger),
            debts: DebtRepository(client: client, logger: logger),
            goals: GoalRepository(client: client, logger: logger),
            goalContributions: PostgresGoalContributionRepository(client: client, logger: logger)
        )
    }
}
