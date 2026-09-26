import Foundation

/// Storage for every resource the service exposes.
struct Repositories: Sendable {
    var subscriptions: any RecordRepository<SubscriptionFields>

    static func inMemory(clock: @escaping @Sendable () -> Date = { Date() }) -> Repositories {
        Repositories(subscriptions: InMemoryRecordRepository(clock: clock))
    }
}
