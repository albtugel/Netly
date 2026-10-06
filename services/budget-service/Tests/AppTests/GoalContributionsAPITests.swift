import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import App

@Suite struct GoalContributionsAPITests {
    let laptop = #"{"name": "Laptop", "targetAmount": 1500, "savedAmount": 300, "targetDate": "2027-09-26", "priority": 8}"#

    @Test func contributionRaisesSavedAmount() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let goal = try TestSupport.decode(GoalFields.Response.self, from: try await api.send(.post, "/api/v1/goals", json: laptop))

            let response = try await api.send(.post, "/api/v1/goals/\(goal.id)/contributions", json: #"{"amount": 200, "note": " September "}"#)
            #expect(response.status == .created)
            let created = try TestSupport.decode(GoalContribution.CreatedResponse.self, from: response)
            #expect(created.contribution.amount == 200)
            #expect(created.contribution.note == "September")
            #expect(created.goal.savedAmount == 500)

            let page = try TestSupport.decode(Page<GoalContribution.Response>.self, from: try await api.send(.get, "/api/v1/goals/\(goal.id)/contributions"))
            #expect(page.items == [created.contribution])
        }
    }

    @Test func contributionPastTargetIsRejected() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let goal = try TestSupport.decode(GoalFields.Response.self, from: try await api.send(.post, "/api/v1/goals", json: laptop))

            let response = try await api.send(.post, "/api/v1/goals/\(goal.id)/contributions", json: #"{"amount": 1200.01}"#)
            #expect(try TestSupport.problem(from: response).errors?.map(\.code) == ["exceeds_target"])

            let page = try TestSupport.decode(Page<GoalContribution.Response>.self, from: try await api.send(.get, "/api/v1/goals/\(goal.id)/contributions"))
            #expect(page.total == 0)
        }
    }

    @Test func validatesAmountAndNote() async throws {
        let token = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let api = APIClient(client: client, token: token)
            let goal = try TestSupport.decode(GoalFields.Response.self, from: try await api.send(.post, "/api/v1/goals", json: laptop))

            let response = try await api.send(.post, "/api/v1/goals/\(goal.id)/contributions", json: #"{"amount": 0, "note": "  "}"#)
            #expect(try TestSupport.problem(from: response).errors?.map(\.field) == ["amount", "note"])
        }
    }

    @Test func anotherUsersGoalIsNotFound() async throws {
        let token = try await TestSupport.token()
        let strangerToken = try await TestSupport.token()
        try await TestSupport.apiApplication().test(.router) { client in
            let goal = try TestSupport.decode(
                GoalFields.Response.self,
                from: try await APIClient(client: client, token: token).send(.post, "/api/v1/goals", json: laptop)
            )
            let stranger = APIClient(client: client, token: strangerToken)
            #expect(try await stranger.send(.post, "/api/v1/goals/\(goal.id)/contributions", json: #"{"amount": 10}"#).status == .notFound)
            #expect(try await stranger.send(.get, "/api/v1/goals/\(goal.id)/contributions").status == .notFound)
        }
    }
}
