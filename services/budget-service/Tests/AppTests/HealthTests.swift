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
