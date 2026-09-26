import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import App

@Suite struct DebtsAPITests {
    typealias Debt = DebtFields.Response

    let loan = #"{"creditor": "Kaspi Bank", "amount": 1200, "dueDate": "2027-03-26"}"#

    @Test func crudRoundTrip() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)

            let created = try await api.send(.post, "/api/v1/debts", json: loan)
            #expect(created.status == .created)
            let debt = try TestSupport.decode(Debt.self, from: created)
            #expect(debt.monthlyPayment == 200)

            let page = try TestSupport.decode(Page<Debt>.self, from: try await api.send(.get, "/api/v1/debts"))
            #expect(page.items == [debt])

            let patched = try TestSupport.decode(Debt.self, from: try await api.send(.patch, "/api/v1/debts/\(debt.id)", json: #"{"amount": 600}"#))
            #expect(patched.monthlyPayment == 100)
            #expect(patched.creditor == "Kaspi Bank")

            #expect(try await api.send(.delete, "/api/v1/debts/\(debt.id)").status == .noContent)
            #expect(try await api.send(.get, "/api/v1/debts/\(debt.id)").status == .notFound)
        }
    }

    @Test func rejectsPastDueDateAndBadAmount() async throws {
        let token = try await TestSupport.token()
        let body = #"{"creditor": "Friend", "amount": -5, "dueDate": "2026-09-26"}"#
        try await TestSupport.apiApplication().test(.router) { client in
            let response = try await APIClient(client: client, token: token).send(.post, "/api/v1/debts", json: body)
            #expect(response.status == .unprocessableContent)
            let problem = try TestSupport.problem(from: response)
            #expect(problem.errors == [
                FieldError(field: "amount", code: "must_be_positive", message: "Must be greater than 0"),
                FieldError(field: "dueDate", code: "must_be_in_future", message: "Must be after 2026-09-26"),
            ])
        }
    }

    @Test func overdueDebtCanStillBeEditedWithoutMovingTheDate() async throws {
        let userID = UUID()
        let token = try await TestSupport.token(userID: userID)
        let repositories = Repositories.inMemory(clock: { TestSupport.now })
        let overdue = try await repositories.debts.create(
            DebtFields(creditor: "Friend", amount: 300, dueDate: CalendarDate("2026-08-01")!),
            userID: userID
        )

        try await TestSupport.apiApplication(repositories: repositories).test(.router) { client in
            let api = APIClient(client: client, token: token)
            let path = "/api/v1/debts/\(overdue.id.uuidString.lowercased())"

            let response = try await api.send(.patch, path, json: #"{"amount": 250}"#)
            #expect(response.status == .ok)
            #expect(try TestSupport.decode(Debt.self, from: response).monthlyPayment == 250)

            let movedToPast = try await api.send(.patch, path, json: #"{"dueDate": "2026-09-01"}"#)
            #expect(movedToPast.status == .unprocessableContent)
        }
    }
}
