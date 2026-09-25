import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import App

@Suite struct HealthTests {
    @Test func healthReturnsOk() async throws {
        let app = buildApplication(configuration: AppConfiguration(hostname: "127.0.0.1", port: 0))

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
