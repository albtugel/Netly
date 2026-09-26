import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import PostgresNIO
import Testing

@testable import App

private let postgresTestURL = ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"]

/// Runs the HTTP API against a real database. Enabled only when `POSTGRES_TEST_URL` is set, e.g.
/// `POSTGRES_TEST_URL=postgres://netly:netly@postgres:5432/netly_budget swift test`.
@Suite(.enabled(if: postgresTestURL != nil), .serialized)
struct PostgresIntegrationTests {
    private func withPostgresAPI(_ body: @escaping @Sendable (any TestClientProtocol) async throws -> Void) async throws {
        let logger = Logger(label: "postgres-tests")
        let client = PostgresClient(configuration: try .init(databaseURL: postgresTestURL!), backgroundLogger: logger)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await client.run() }
            try await Schema.migrate(client: client, logger: logger)
            let router = buildRouter(
                keys: await TestSupport.keys(),
                repositories: .postgres(client: client, logger: logger),
                clock: { TestSupport.now }
            )
            try await Application(router: router).test(.router) { client in
                try await body(client)
            }
            group.cancelAll()
        }
    }

    @Test func subscriptionRoundTripKeepsExactValues() async throws {
        let token = try await TestSupport.token()
        let strangerToken = try await TestSupport.token()
        try await withPostgresAPI { client in
            let api = APIClient(client: client, token: token)
            let body = #"{"name": "Spotify", "price": 4.99, "billingCycle": "monthly", "nextChargeDate": "2026-10-01"}"#
            let created = try TestSupport.decode(SubscriptionFields.Response.self, from: try await api.send(.post, "/api/v1/subscriptions", json: body))
            #expect(created.price == Decimal(string: "4.99"))
            #expect(created.nextChargeDate.description == "2026-10-01")

            let fetched = try TestSupport.decode(SubscriptionFields.Response.self, from: try await api.send(.get, "/api/v1/subscriptions/\(created.id)"))
            #expect(fetched == created)

            let foreign = try await APIClient(client: client, token: strangerToken).send(.get, "/api/v1/subscriptions/\(created.id)")
            #expect(foreign.status == .notFound)

            let patched = try TestSupport.decode(
                SubscriptionFields.Response.self,
                from: try await api.send(.patch, "/api/v1/subscriptions/\(created.id)", json: #"{"billingCycle": "yearly", "price": 59.88}"#)
            )
            #expect(patched.monthlyCost == Decimal(string: "4.99"))
            #expect(patched.updatedAt >= created.updatedAt)

            #expect(try await api.send(.delete, "/api/v1/subscriptions/\(created.id)").status == .noContent)
            #expect(try await api.send(.delete, "/api/v1/subscriptions/\(created.id)").status == .notFound)
        }
    }

    @Test func listPagesAndCountsPerUser() async throws {
        let token = try await TestSupport.token()
        try await withPostgresAPI { client in
            let api = APIClient(client: client, token: token)
            for creditor in ["A", "B", "C"] {
                let body = #"{"creditor": "\#(creditor)", "amount": 100.5, "dueDate": "2027-01-15"}"#
                #expect(try await api.send(.post, "/api/v1/debts", json: body).status == .created)
            }
            let page = try TestSupport.decode(Page<DebtFields.Response>.self, from: try await api.send(.get, "/api/v1/debts?limit=2&offset=2"))
            #expect(page.total == 3)
            #expect(page.items.map(\.creditor) == ["C"])
            #expect(page.items.first?.amount == Decimal(string: "100.5"))
        }
    }

    @Test func goalRoundTrip() async throws {
        let token = try await TestSupport.token()
        try await withPostgresAPI { client in
            let api = APIClient(client: client, token: token)
            let body = #"{"name": "Laptop", "targetAmount": 1500, "savedAmount": 300.25, "targetDate": "2027-09-26", "priority": 8}"#
            let goal = try TestSupport.decode(GoalFields.Response.self, from: try await api.send(.post, "/api/v1/goals", json: body))
            #expect(goal.status == .active)
            #expect(goal.savedAmount == Decimal(string: "300.25"))

            let completed = try TestSupport.decode(
                GoalFields.Response.self,
                from: try await api.send(.patch, "/api/v1/goals/\(goal.id)", json: #"{"status": "completed", "savedAmount": 1500}"#)
            )
            #expect(completed.status == .completed)
            #expect(completed.priority == 8)
            #expect(completed.requiredMonthlyContribution == 0)
        }
    }
}
