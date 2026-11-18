import Foundation
import HTTPTypes
import Hummingbird

/// What the user has to pay every month: subscriptions, debts and the savings goals' required contributions.
struct CommitmentsSummary: ResponseCodable, Equatable {
    struct Counts: Codable, Equatable, Sendable {
        let subscriptions: Int
        let debts: Int
        /// Active goals only; the others require nothing.
        let goals: Int
    }

    let subscriptionsMonthly: Decimal
    let debtsMonthly: Decimal
    let goalsRequiredMonthly: Decimal
    let totalMonthlyCommitments: Decimal
    let counts: Counts
    let computedAt: Date
}

/// `GET /api/v1/summary`: the monthly commitments, computed from three reads and cached per user.
struct SummaryController: Sendable {
    static let cacheHeader = HTTPField.Name("X-Cache")!
    static let defaultComputeTimeout = Duration.seconds(5)

    let repositories: Repositories
    let cache: SummaryCache
    let clock: @Sendable () -> Date
    /// How long a computation may take. A database that is down makes the pool wait for a connection
    /// instead of failing, so without this limit a cache miss would hang until the client gives up.
    var computeTimeout = SummaryController.defaultComputeTimeout

    func addRoutes(to api: RouterGroup<BudgetRequestContext>) {
        api.get("summary", use: show)
    }

    /// The `X-Cache` response header tells whether the body came from the cache (`HIT`) or was computed (`MISS`).
    @Sendable func show(_ request: Request, context: BudgetRequestContext) async throws -> EditedResponse<CommitmentsSummary> {
        let userID = try context.requireIdentity().id
        let (summary, isHit) = try await cache.summary(for: userID) {
            try await Self.withTimeout(computeTimeout) { try await compute(for: userID) }
        }
        return EditedResponse(headers: [Self.cacheHeader: isHit ? "HIT" : "MISS"], response: summary)
    }

    private static func withTimeout<Value: Sendable>(
        _ timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw APIError.serviceUnavailable("The summary could not be computed in time; try again later")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func compute(for userID: UUID) async throws -> CommitmentsSummary {
        let now = clock()
        let today = CalendarDate(now)
        let subscriptions = try await Self.all(repositories.subscriptions, userID: userID)
        let debts = try await Self.all(repositories.debts, userID: userID)
        let activeGoals = try await Self.all(
            repositories.goals,
            userID: userID,
            filters: GoalFields.listFilters.map { AppliedFilter(filter: $0, value: GoalStatus.active.rawValue) }
        )

        let subscriptionsMonthly = subscriptions
            .map { MonthlyEquivalent.subscriptionCost(price: $0.fields.price, cycle: $0.fields.billingCycle) }
            .reduce(0, +)
        let debtsMonthly = debts
            .map { MonthlyEquivalent.installment(amount: $0.fields.amount, from: today, until: $0.fields.dueDate) }
            .reduce(0, +)
        let goalsRequiredMonthly = activeGoals
            .map { $0.fields.requiredMonthlyContribution(today: today) }
            .reduce(0, +)
        return CommitmentsSummary(
            subscriptionsMonthly: subscriptionsMonthly,
            debtsMonthly: debtsMonthly,
            goalsRequiredMonthly: goalsRequiredMonthly,
            totalMonthlyCommitments: subscriptionsMonthly + debtsMonthly + goalsRequiredMonthly,
            counts: .init(subscriptions: subscriptions.count, debts: debts.count, goals: activeGoals.count),
            computedAt: now
        )
    }

    /// Every record of the user, read page by page.
    private static func all<Fields: ResourceFields>(
        _ repository: any RecordRepository<Fields>,
        userID: UUID,
        filters: [AppliedFilter<Fields>] = []
    ) async throws -> [Record<Fields>] {
        var records: [Record<Fields>] = []
        while true {
            let page = try await repository.list(userID: userID, filters: filters, limit: Pagination.maximumLimit, offset: records.count)
            records += page.records
            if page.records.isEmpty || records.count >= page.total {
                return records
            }
        }
    }
}
