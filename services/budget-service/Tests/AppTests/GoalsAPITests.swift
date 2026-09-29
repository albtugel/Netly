import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import App

@Suite struct GoalsAPITests {
    typealias Goal = GoalFields.Response

    let laptop = #"{"name": "Laptop", "targetAmount": 1500, "savedAmount": 300, "targetDate": "2027-09-26", "priority": 8}"#

    @Test func createAppliesDefaultsAndComputesContribution() async throws {
        let token = try await TestSupport.token()
        let body = #"{"name": "Trip", "targetAmount": 1200, "targetDate": "2027-03-26", "priority": 3}"#
        try await TestSupport.apiApplication().test(.router) { client in
            let response = try await APIClient(client: client, token: token).send(.post, "/api/v1/goals", json: body)
            #expect(response.status == .created)
            let goal = try TestSupport.decode(Goal.self, from: response)
            #expect(goal.savedAmount == 0)
            #expect(goal.status == .active)
            #expect(goal.requiredMonthlyContribution == 200)
        }
    }

    @Test func reportsAllRuleViolationsTogether() async throws {
        let token = try await TestSupport.token()
        let body = #"{"name": "Car", "targetAmount": 100, "savedAmount": 150, "targetDate": "2020-01-01", "priority": 11}"#
        try await TestSupport.apiApplication().test(.router) { client in
            let response = try await APIClient(client: client, token: token).send(.post, "/api/v1/goals", json: body)
            let problem = try TestSupport.problem(from: response)
            #expect(problem.detail == "3 fields are invalid")
            #expect(problem.errors?.map(\.code) == ["exceeds_target", "must_be_in_future", "out_of_range"])
            #expect(problem.errors?.map(\.field) == ["savedAmount", "targetDate", "priority"])
        }
    }

    @Test func crossFieldRuleSkipsFieldsThatAreAlreadyInvalid() async throws {
        let token = try await TestSupport.token()
        let body = #"{"name": "Car", "targetAmount": 100, "savedAmount": 150.555, "targetDate": "2028-01-01", "priority": 5}"#
        try await TestSupport.apiApplication().test(.router) { client in
            let response = try await APIClient(client: client, token: token).send(.post, "/api/v1/goals", json: body)
            let problem = try TestSupport.problem(from: response)
            #expect(problem.errors == [FieldError(field: "savedAmount", code: "too_precise", message: "Must have at most 2 decimal places")])
        }
    }

    @Test func patchValidatesAgainstStoredValues() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let goal = try TestSupport.decode(Goal.self, from: try await api.send(.post, "/api/v1/goals", json: laptop))
            #expect(goal.requiredMonthlyContribution == 100)

            let tooMuch = try await api.send(.patch, "/api/v1/goals/\(goal.id)", json: #"{"savedAmount": 1600}"#)
            #expect(try TestSupport.problem(from: tooMuch).errors?.first?.code == "exceeds_target")

            let completed = try await api.send(.patch, "/api/v1/goals/\(goal.id)", json: #"{"savedAmount": 1500, "status": "completed"}"#)
            #expect(completed.status == .ok)
            #expect(try TestSupport.decode(Goal.self, from: completed).requiredMonthlyContribution == 0)
        }
    }

    @Test func listAndDelete() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let goal = try TestSupport.decode(Goal.self, from: try await api.send(.post, "/api/v1/goals", json: laptop))

            let page = try TestSupport.decode(Page<Goal>.self, from: try await api.send(.get, "/api/v1/goals"))
            #expect(page.items.map(\.id) == [goal.id])

            #expect(try await api.send(.delete, "/api/v1/goals/\(goal.id)").status == .noContent)
            let empty = try TestSupport.decode(Page<Goal>.self, from: try await api.send(.get, "/api/v1/goals"))
            #expect(empty.total == 0)
        }
    }
}
