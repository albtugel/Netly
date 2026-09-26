import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import App

@Suite struct SubscriptionsAPITests {
    typealias Subscription = SubscriptionFields.Response

    let netflix = #"{"name": "  Netflix ", "price": 119.88, "billingCycle": "yearly", "nextChargeDate": "2026-10-15"}"#

    @Test func createReturnsCreatedWithLocationAndComputedCost() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let response = try await api.send(.post, "/api/v1/subscriptions", json: netflix)

            #expect(response.status == .created)
            let subscription = try TestSupport.decode(Subscription.self, from: response)
            #expect(response.headers[.location] == "/api/v1/subscriptions/\(subscription.id)")
            #expect(subscription.name == "Netflix")
            #expect(subscription.price == Decimal(string: "119.88"))
            #expect(subscription.billingCycle == .yearly)
            #expect(subscription.nextChargeDate.description == "2026-10-15")
            #expect(subscription.monthlyCost == Decimal(string: "9.99"))
            #expect(subscription.createdAt == TestSupport.now)
        }
    }

    @Test func createReportsEveryInvalidField() async throws {
        let token = try await TestSupport.token()
        let body = #"{"name": "", "price": 0, "billingCycle": "daily", "nextChargeDate": "2026-10-15"}"#
        try await TestSupport.apiApplication().test(.router) { client in
            let response = try await APIClient(client: client, token: token).send(.post, "/api/v1/subscriptions", json: body)
            #expect(response.status == .unprocessableContent)
            // The enum fails while decoding, before business rules run, so it is reported on its own.
            let problem = try TestSupport.problem(from: response)
            #expect(problem.errors == [
                FieldError(field: "billingCycle", code: "invalid_value", message: "Must be one of: weekly, monthly, quarterly, yearly")
            ])
        }

        let rulesBody = #"{"name": "", "price": 0, "billingCycle": "monthly", "nextChargeDate": "2026-10-15"}"#
        try await TestSupport.apiApplication().test(.router) { client in
            let response = try await APIClient(client: client, token: token).send(.post, "/api/v1/subscriptions", json: rulesBody)
            let problem = try TestSupport.problem(from: response)
            #expect(problem.errors?.map(\.field) == ["name", "price"])
            #expect(problem.errors?.map(\.code) == ["blank", "must_be_positive"])
        }
    }

    @Test func listPaginatesOwnRecordsOnly() async throws {
        let token = try await TestSupport.token()
        let strangerToken = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            for name in ["A", "B", "C"] {
                _ = try await api.send(.post, "/api/v1/subscriptions", json: #"{"name": "\#(name)", "price": 5, "billingCycle": "monthly", "nextChargeDate": "2026-10-01"}"#)
            }
            _ = try await APIClient(client: client, token: strangerToken).send(.post, "/api/v1/subscriptions", json: netflix)

            let response = try await api.send(.get, "/api/v1/subscriptions?limit=2&offset=1")
            #expect(response.status == .ok)
            let page = try TestSupport.decode(Page<Subscription>.self, from: response)
            #expect(page.items.map(\.name) == ["B", "C"])
            #expect(page.total == 3)
            #expect(page.limit == 2)
            #expect(page.offset == 1)
        }
    }

    @Test func listValidatesPaging() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let outOfRange = try TestSupport.problem(from: try await api.send(.get, "/api/v1/subscriptions?limit=0&offset=-1"))
            #expect(outOfRange.errors?.map(\.field) == ["limit", "offset"])

            let notNumber = try TestSupport.problem(from: try await api.send(.get, "/api/v1/subscriptions?limit=ten"))
            #expect(notNumber.errors == [FieldError(field: "limit", code: "invalid_type", message: "Expected integer")])
        }
    }

    @Test func showHidesOtherUsersRecords() async throws {
        let token = try await TestSupport.token()
        let strangerToken = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let created = try await APIClient(client: client, token: token).send(.post, "/api/v1/subscriptions", json: netflix)
            let id = try TestSupport.decode(Subscription.self, from: created).id

            let own = try await APIClient(client: client, token: token).send(.get, "/api/v1/subscriptions/\(id)")
            #expect(own.status == .ok)

            let foreign = try await APIClient(client: client, token: strangerToken).send(.get, "/api/v1/subscriptions/\(id)")
            #expect(foreign.status == .notFound)
            let problem = try TestSupport.problem(from: foreign)
            #expect(problem.detail == "Subscription \(id) was not found")
        }
    }

    @Test func showRejectsMalformedID() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let response = try await APIClient(client: client, token: token).send(.get, "/api/v1/subscriptions/42")
            #expect(response.status == .unprocessableContent)
            #expect(try TestSupport.problem(from: response).errors?.first?.field == "id")
        }
    }

    @Test func patchMergesAndRecomputes() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let id = try TestSupport.decode(Subscription.self, from: try await api.send(.post, "/api/v1/subscriptions", json: netflix)).id

            let response = try await api.send(.patch, "/api/v1/subscriptions/\(id)", json: #"{"billingCycle": "monthly", "price": 12.5}"#)
            #expect(response.status == .ok)
            let updated = try TestSupport.decode(Subscription.self, from: response)
            #expect(updated.name == "Netflix")
            #expect(updated.monthlyCost == Decimal(string: "12.5"))
        }
    }

    @Test func invalidPatchLeavesRecordUnchanged() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let id = try TestSupport.decode(Subscription.self, from: try await api.send(.post, "/api/v1/subscriptions", json: netflix)).id

            let response = try await api.send(.patch, "/api/v1/subscriptions/\(id)", json: #"{"name": " ", "price": 2000000}"#)
            #expect(response.status == .unprocessableContent)
            #expect(try TestSupport.problem(from: response).errors?.map(\.code) == ["blank", "too_large"])

            let current = try TestSupport.decode(Subscription.self, from: try await api.send(.get, "/api/v1/subscriptions/\(id)"))
            #expect(current.name == "Netflix")
            #expect(current.price == Decimal(string: "119.88"))
        }
    }

    @Test func deleteRemovesRecord() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let id = try TestSupport.decode(Subscription.self, from: try await api.send(.post, "/api/v1/subscriptions", json: netflix)).id

            #expect(try await api.send(.delete, "/api/v1/subscriptions/\(id)").status == .noContent)
            #expect(try await api.send(.get, "/api/v1/subscriptions/\(id)").status == .notFound)
            #expect(try await api.send(.delete, "/api/v1/subscriptions/\(id)").status == .notFound)
        }
    }

    @Test func requiresToken() async throws {
        try await TestSupport.apiApplication().test(.router) { client in
            try await client.execute(uri: "/api/v1/subscriptions", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }
}
