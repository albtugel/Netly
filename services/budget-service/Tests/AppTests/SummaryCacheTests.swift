import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import Testing

@testable import App

/// A clock the test moves by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = TestSupport.now

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Delegates to another repository, counts `list` calls (the summary's only reads) and can be made to fail them,
/// like a database that went away.
private actor CountingRepository<Fields: ResourceFields>: RecordRepository {
    struct DatabaseDown: Error {}

    private let base: any RecordRepository<Fields>
    private(set) var listCalls = 0
    var isFailing = false

    init(_ base: any RecordRepository<Fields>) {
        self.base = base
    }

    func setFailing(_ failing: Bool) {
        isFailing = failing
    }

    func list(userID: UUID, filters: [AppliedFilter<Fields>], limit: Int, offset: Int) async throws -> (records: [Record<Fields>], total: Int) {
        listCalls += 1
        if isFailing { throw DatabaseDown() }
        return try await base.list(userID: userID, filters: filters, limit: limit, offset: offset)
    }

    func find(id: UUID, userID: UUID) async throws -> Record<Fields>? {
        try await base.find(id: id, userID: userID)
    }

    func create(_ fields: Fields, userID: UUID) async throws -> Record<Fields> {
        try await base.create(fields, userID: userID)
    }

    func update(id: UUID, userID: UUID, fields: Fields) async throws -> Record<Fields>? {
        try await base.update(id: id, userID: userID, fields: fields)
    }

    func delete(id: UUID, userID: UUID) async throws -> Bool {
        try await base.delete(id: id, userID: userID)
    }
}

private final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(message: String, metadata: Logger.Metadata)] = []

    var messages: [String] {
        lock.withLock { recorded.map(\.message) }
    }

    func metadata(of message: String) -> Logger.Metadata? {
        lock.withLock { recorded.first { $0.message == message }?.metadata }
    }

    func record(_ message: String, _ metadata: Logger.Metadata) {
        lock.withLock { recorded.append((message, metadata)) }
    }
}

private struct RecordingLogHandler: LogHandler {
    let recorder: LogRecorder
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        recorder.record("\(event.message)", event.metadata ?? [:])
    }
}

/// The router under test with counting repositories, a manual clock and recorded logs.
private struct Harness {
    let subscriptions: CountingRepository<SubscriptionFields>
    let debts: CountingRepository<DebtFields>
    let goals: CountingRepository<GoalFields>
    let clock = ManualClock()
    let logs = LogRecorder()
    let ttl: TimeInterval

    init(ttl: TimeInterval = 60) {
        self.ttl = ttl
        subscriptions = CountingRepository(InMemoryRecordRepository<SubscriptionFields>(clock: { TestSupport.now }))
        debts = CountingRepository(InMemoryRecordRepository<DebtFields>(clock: { TestSupport.now }))
        goals = CountingRepository(InMemoryRecordRepository<GoalFields>(clock: { TestSupport.now }))
    }

    /// Every `list` call of the three repositories: one summary computation reads each of them once.
    var reads: Int {
        get async { await subscriptions.listCalls + debts.listCalls + goals.listCalls }
    }

    func application() async -> some ApplicationProtocol {
        let now: @Sendable () -> Date = { TestSupport.now }
        let repositories = Repositories(
            subscriptions: subscriptions,
            debts: debts,
            goals: goals,
            goalContributions: ContributionsToCountedGoals(goals: goals, clock: now)
        )
        let recorder = logs
        let clock = clock
        let router = buildRouter(
            keys: await TestSupport.keys(),
            repositories: repositories,
            clock: { clock.now },
            summaryCacheTTL: ttl,
            logger: Logger(label: "summary-cache-tests") { _ in RecordingLogHandler(recorder: recorder) }
        )
        return Application(router: router)
    }
}

/// Contributions that raise `savedAmount` in the harness's goal repository, like the real repositories do.
private struct ContributionsToCountedGoals: GoalContributionRepository {
    let goals: CountingRepository<GoalFields>
    let clock: @Sendable () -> Date

    func contribute(goalID: UUID, userID: UUID, amount: Decimal, note: String?) async throws -> (contribution: GoalContribution, goal: Record<GoalFields>)? {
        guard var fields = try await goals.find(id: goalID, userID: userID)?.fields else { return nil }
        fields.savedAmount += amount
        guard let goal = try await goals.update(id: goalID, userID: userID, fields: fields) else { return nil }
        return (GoalContribution(id: UUID(), goalID: goalID, amount: amount, note: note, createdAt: clock()), goal)
    }

    func list(goalID: UUID, userID: UUID, limit: Int, offset: Int) async throws -> (records: [GoalContribution], total: Int)? {
        try await goals.find(id: goalID, userID: userID) == nil ? nil : ([], 0)
    }
}

private struct CachedSummary {
    let summary: CommitmentsSummary
    let header: String?
}

private func getSummary(_ api: APIClient) async throws -> CachedSummary {
    let response = try await api.send(.get, "/api/v1/summary")
    #expect(response.status == .ok)
    return CachedSummary(
        summary: try TestSupport.decode(CommitmentsSummary.self, from: response),
        header: response.headers[SummaryController.cacheHeader]
    )
}

@Suite struct SummaryCacheTests {
    let netflix = #"{"name": "Netflix", "price": 10, "billingCycle": "monthly", "nextChargeDate": "2026-10-15"}"#

    @Test func summaryAddsUpSubscriptionsDebtsAndActiveGoals() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            _ = try await api.send(.post, "/api/v1/subscriptions", json: #"{"name": "Netflix", "price": 119.88, "billingCycle": "yearly", "nextChargeDate": "2026-10-15"}"#)
            _ = try await api.send(.post, "/api/v1/debts", json: #"{"creditor": "Bank", "amount": 1200, "dueDate": "2026-12-26"}"#)
            _ = try await api.send(.post, "/api/v1/goals", json: #"{"name": "Laptop", "targetAmount": 1500, "savedAmount": 300, "targetDate": "2027-09-26", "priority": 8}"#)
            _ = try await api.send(.post, "/api/v1/goals", json: #"{"name": "Old", "targetAmount": 500, "targetDate": "2027-09-26", "priority": 1, "status": "archived"}"#)

            let summary = try await getSummary(api).summary
            #expect(summary.subscriptionsMonthly == Decimal(string: "9.99"))
            #expect(summary.debtsMonthly == 400)
            #expect(summary.goalsRequiredMonthly == 100)
            #expect(summary.totalMonthlyCommitments == Decimal(string: "509.99"))
            #expect(summary.counts == .init(subscriptions: 1, debts: 1, goals: 1))
            #expect(summary.computedAt == TestSupport.now)
        }
    }

    @Test func summaryReadsEveryPageOfRecords() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            for number in 1...(Pagination.maximumLimit + 1) {
                _ = try await api.send(.post, "/api/v1/subscriptions", json: #"{"name": "Service \#(number)", "price": 1, "billingCycle": "monthly", "nextChargeDate": "2026-10-15"}"#)
            }
            let summary = try await getSummary(api).summary
            #expect(summary.counts.subscriptions == Pagination.maximumLimit + 1)
            #expect(summary.subscriptionsMonthly == Decimal(Pagination.maximumLimit + 1))
        }
    }

    @Test func emptyAccountHasZeroCommitments() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let summary = try await getSummary(APIClient(client: client, token: token)).summary
            #expect(summary.totalMonthlyCommitments == 0)
            #expect(summary.counts == .init(subscriptions: 0, debts: 0, goals: 0))
        }
    }

    @Test func repeatRequestWithinTTLDoesNotReadTheRepositoriesAgain() async throws {
        let harness = Harness()
        let token = try await TestSupport.token()
        try await harness.application().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let first = try await getSummary(api)
            #expect(first.header == "MISS")
            #expect(await harness.reads == 3)

            harness.clock.advance(by: 59)
            let second = try await getSummary(api)
            #expect(second.header == "HIT")
            #expect(second.summary == first.summary)
            #expect(await harness.reads == 3)
        }
    }

    @Test func entryExpiresAfterTTL() async throws {
        let harness = Harness(ttl: 60)
        let token = try await TestSupport.token()
        try await harness.application().test(.router) { client in
            let api = APIClient(client: client, token: token)
            _ = try await getSummary(api)

            harness.clock.advance(by: 61)
            #expect(try await getSummary(api).header == "MISS")
            #expect(await harness.reads == 6)
            #expect(try await getSummary(api).header == "HIT")
        }
    }

    @Test func zeroTTLDisablesTheCache() async throws {
        let harness = Harness(ttl: 0)
        let token = try await TestSupport.token()
        try await harness.application().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let first = try await getSummary(api)
            let second = try await getSummary(api)
            #expect([first.header, second.header] == ["MISS", "MISS"])
            #expect(await harness.reads == 6)
        }
    }

    /// After every write the next read must recompute and show the new numbers, never the cached ones.
    @Test func everyWriteInvalidatesTheSummary() async throws {
        let harness = Harness()
        let token = try await TestSupport.token()
        try await harness.application().test(.router) { client in
            let api = APIClient(client: client, token: token)

            /// Primes the cache, performs the write and expects the next summary to be recomputed with `total`.
            func write(_ method: HTTPRequest.Method, _ path: String, json: String? = nil, total: Decimal, expecting status: HTTPResponse.Status) async throws -> TestResponse {
                _ = try await getSummary(api)
                #expect(try await getSummary(api).header == "HIT")
                let response = try await api.send(method, path, json: json)
                #expect(response.status == status)
                let after = try await getSummary(api)
                #expect(after.header == "MISS", "\(method) \(path) left a stale summary")
                #expect(after.summary.totalMonthlyCommitments == total, "\(method) \(path)")
                return response
            }

            let subscription = try await TestSupport.decode(SubscriptionFields.Response.self, from: write(.post, "/api/v1/subscriptions", json: netflix, total: 10, expecting: .created))
            _ = try await write(.patch, "/api/v1/subscriptions/\(subscription.id)", json: #"{"price": 25}"#, total: 25, expecting: .ok)
            let debt = try await TestSupport.decode(DebtFields.Response.self, from: write(.post, "/api/v1/debts", json: #"{"creditor": "Bank", "amount": 1200, "dueDate": "2026-12-26"}"#, total: 425, expecting: .created))
            _ = try await write(.patch, "/api/v1/debts/\(debt.id)", json: #"{"amount": 600}"#, total: 225, expecting: .ok)
            let goal = try await TestSupport.decode(GoalFields.Response.self, from: write(.post, "/api/v1/goals", json: #"{"name": "Laptop", "targetAmount": 1200, "targetDate": "2027-09-26", "priority": 8}"#, total: 325, expecting: .created))
            _ = try await write(.patch, "/api/v1/goals/\(goal.id)", json: #"{"targetAmount": 1800}"#, total: 375, expecting: .ok)
            _ = try await write(.post, "/api/v1/goals/\(goal.id)/contributions", json: #"{"amount": 600}"#, total: 325, expecting: .created)
            _ = try await write(.delete, "/api/v1/goals/\(goal.id)", total: 225, expecting: .noContent)
            _ = try await write(.delete, "/api/v1/debts/\(debt.id)", total: 25, expecting: .noContent)
            _ = try await write(.delete, "/api/v1/subscriptions/\(subscription.id)", total: 0, expecting: .noContent)
        }
    }

    @Test func rejectedWriteKeepsTheCachedSummary() async throws {
        let harness = Harness()
        let token = try await TestSupport.token()
        try await harness.application().test(.router) { client in
            let api = APIClient(client: client, token: token)
            _ = try await getSummary(api)

            let invalid = try await api.send(.post, "/api/v1/subscriptions", json: #"{"name": "", "price": 0, "billingCycle": "monthly", "nextChargeDate": "2026-10-15"}"#)
            #expect(invalid.status == .unprocessableContent)
            #expect(try await getSummary(api).header == "HIT")
        }
    }

    @Test func eachUserHasOwnEntry() async throws {
        let harness = Harness()
        let (aliceToken, bobToken) = (try await TestSupport.token(), try await TestSupport.token())
        try await harness.application().test(.router) { client in
            let aliceAPI = APIClient(client: client, token: aliceToken)
            let bobAPI = APIClient(client: client, token: bobToken)
            _ = try await aliceAPI.send(.post, "/api/v1/subscriptions", json: netflix)
            #expect(try await getSummary(aliceAPI).summary.totalMonthlyCommitments == 10)
            #expect(try await getSummary(bobAPI).summary.totalMonthlyCommitments == 0)

            // Bob's write drops Bob's entry only.
            _ = try await bobAPI.send(.post, "/api/v1/debts", json: #"{"creditor": "Bank", "amount": 1200, "dueDate": "2026-12-26"}"#)
            #expect(try await getSummary(aliceAPI).header == "HIT")
            let bobAfter = try await getSummary(bobAPI)
            #expect(bobAfter.header == "MISS")
            #expect(bobAfter.summary.totalMonthlyCommitments == 400)
        }
    }

    @Test func failedComputationIsNotCachedAndTheServiceRecovers() async throws {
        let harness = Harness()
        let token = try await TestSupport.token()
        try await harness.application().test(.router) { client in
            let api = APIClient(client: client, token: token)
            await harness.debts.setFailing(true)

            for _ in 1...2 {
                let response = try await api.send(.get, "/api/v1/summary")
                #expect(response.status == .internalServerError)
                #expect(try TestSupport.errorBody(from: response).code == "internal_error")
            }
            // Both failures reached the repository: the first was not remembered.
            #expect(await harness.debts.listCalls == 2)

            await harness.debts.setFailing(false)
            #expect(try await getSummary(api).header == "MISS")
            #expect(try await getSummary(api).header == "HIT")
        }
    }

    @Test func cachedSummaryIsStillServedWhileTheStorageIsDown() async throws {
        let harness = Harness()
        let token = try await TestSupport.token()
        try await harness.application().test(.router) { client in
            let api = APIClient(client: client, token: token)
            _ = try await getSummary(api)
            await harness.subscriptions.setFailing(true)
            await harness.debts.setFailing(true)
            await harness.goals.setFailing(true)

            #expect(try await getSummary(api).header == "HIT")

            harness.clock.advance(by: 61)
            let response = try await api.send(.get, "/api/v1/summary")
            #expect(response.status == .internalServerError)
        }
    }

    @Test func unauthenticatedRequestIsRejectedBeforeTheCache() async throws {
        let harness = Harness()
        try await harness.application().test(.router) { client in
            let response = try await client.execute(uri: "/api/v1/summary", method: .get)
            #expect(response.status == .unauthorized)
            #expect(await harness.reads == 0)
        }
    }

    @Test func logsMissStoreHitInvalidationExpiryAndFailure() async throws {
        let harness = Harness()
        let userID = UUID()
        let token = try await TestSupport.token(userID: userID)
        try await harness.application().test(.router) { client in
            let api = APIClient(client: client, token: token)
            _ = try await getSummary(api)
            _ = try await getSummary(api)
            _ = try await api.send(.post, "/api/v1/subscriptions", json: netflix)
            _ = try await getSummary(api)
            harness.clock.advance(by: 61)
            _ = try await getSummary(api)
            await harness.debts.setFailing(true)
            harness.clock.advance(by: 61)
            _ = try await api.send(.get, "/api/v1/summary")
        }

        #expect(harness.logs.messages == [
            "summary cache miss", "summary cache store",
            "summary cache hit",
            "summary cache invalidated",
            "summary cache miss", "summary cache store",
            "summary cache expired", "summary cache miss", "summary cache store",
            "summary cache expired", "summary cache miss", "summary computation failed",
        ])
        let user = Logger.MetadataValue.string(userID.uuidString.lowercased())
        #expect(harness.logs.metadata(of: "summary cache hit")?["userId"] == user)
        #expect(harness.logs.metadata(of: "summary cache store")?["ttlSeconds"] == "60")
        #expect(harness.logs.metadata(of: "summary cache invalidated")?["reason"] == "subscriptions created")
        #expect(harness.logs.metadata(of: "summary computation failed")?["userId"] == user)
    }
}

@Suite struct SummaryCacheUnitTests {
    private let summary = CommitmentsSummary(
        subscriptionsMonthly: 1,
        debtsMonthly: 0,
        goalsRequiredMonthly: 0,
        totalMonthlyCommitments: 1,
        counts: .init(subscriptions: 1, debts: 0, goals: 0),
        computedAt: TestSupport.now
    )

    @Test func fullCacheEvictsTheOldestEntry() async throws {
        let clock = ManualClock()
        let cache = SummaryCache(ttl: 60, capacity: 2, clock: { clock.now })
        let (alice, bob, carol) = (UUID(), UUID(), UUID())
        let summary = summary

        for user in [alice, bob, carol] {
            _ = try await cache.summary(for: user) { summary }
            clock.advance(by: 1)
        }
        #expect(try await cache.summary(for: alice) { summary }.isHit == false)
        #expect(try await cache.summary(for: carol) { summary }.isHit == true)
    }

    @Test func resultComputedAcrossAnInvalidationIsNotStored() async throws {
        let cache = SummaryCache(ttl: 60)
        let user = UUID()
        let summary = summary

        _ = try await cache.summary(for: user) {
            // A write lands while the summary is being computed from the old data.
            await cache.invalidate(userID: user, reason: "goals updated")
            return summary
        }
        #expect(try await cache.summary(for: user) { summary }.isHit == false)
        #expect(try await cache.summary(for: user) { summary }.isHit == true)
    }
}
