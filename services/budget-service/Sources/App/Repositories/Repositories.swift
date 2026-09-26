import Foundation

/// Storage for every resource the service exposes.
struct Repositories: Sendable {
    var subscriptions: any RecordRepository<SubscriptionFields>
    var debts: any RecordRepository<DebtFields>
    var goals: any RecordRepository<GoalFields>

    static func inMemory(clock: @escaping @Sendable () -> Date = { Date() }) -> Repositories {
        Repositories(
            subscriptions: InMemoryRecordRepository(clock: clock),
            debts: InMemoryRecordRepository(clock: clock),
            goals: InMemoryRecordRepository(clock: clock)
        )
    }
}
