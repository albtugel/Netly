import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import App

@Suite struct HealthTests {
    @Test func healthReturnsOk() async throws {
        let app = Application(router: buildRouter(keys: await TestSupport.keys(), repositories: .inMemory()))
        try await app.test(.router) { client in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
                let body = try JSONDecoder().decode(HealthResponse.self, from: response.body)
                #expect(body.status == "ok")
                #expect(body.service == "netly-budget")
            }
        }
    }
}

@Suite struct AppConfigurationTests {
    @Test func rejectsShortJWTSecret() {
        #expect(throws: AppConfiguration.InvalidConfiguration.self) {
            var environment = DatabaseConfigurationTests.composeEnvironment
            environment["JWT_SECRET"] = "short"
            try AppConfiguration.fromEnvironment(environment)
        }
    }

    @Test func requiresDatabaseSettings() {
        #expect(throws: AppConfiguration.InvalidConfiguration.self) {
            try AppConfiguration.fromEnvironment([:])
        }
    }

    @Test func defaultsToDevelopmentSecretAndPort() throws {
        let configuration = try AppConfiguration.fromEnvironment(DatabaseConfigurationTests.composeEnvironment)
        #expect(configuration.port == 8082)
        #expect(configuration.jwtSecret == AppConfiguration.developmentJWTSecret)
    }
}

@Suite struct ProtectedRoutesTests {
    static let id = UUID().uuidString

    @Test(arguments: [
        (HTTPRequest.Method.get, "/api/v1/subscriptions"),
        (.post, "/api/v1/subscriptions"),
        (.get, "/api/v1/subscriptions/\(id)"),
        (.patch, "/api/v1/subscriptions/\(id)"),
        (.delete, "/api/v1/subscriptions/\(id)"),
        (.get, "/api/v1/debts"),
        (.post, "/api/v1/debts"),
        (.get, "/api/v1/debts/\(id)"),
        (.patch, "/api/v1/debts/\(id)"),
        (.delete, "/api/v1/debts/\(id)"),
        (.get, "/api/v1/goals"),
        (.post, "/api/v1/goals"),
        (.get, "/api/v1/goals/\(id)"),
        (.patch, "/api/v1/goals/\(id)"),
        (.delete, "/api/v1/goals/\(id)"),
        (.get, "/api/v1/goals/\(id)/contributions"),
        (.post, "/api/v1/goals/\(id)/contributions"),
    ])
    func everyBudgetRouteRequiresAToken(method: HTTPRequest.Method, path: String) async throws {
        try await TestSupport.apiApplication().test(.router) { client in
            let response = try await client.execute(uri: path, method: method, body: ByteBuffer(json: "{}"))
            #expect(response.status == .unauthorized)
            #expect(try TestSupport.errorBody(from: response).code == "unauthorized")
        }
    }
}
