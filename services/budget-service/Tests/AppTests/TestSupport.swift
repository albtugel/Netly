import Foundation
import Hummingbird
import HummingbirdTesting
import JWTKit
import Testing

@testable import App

enum TestSupport {
    static let secret = "test-secret-that-is-at-least-32-bytes"

    static func keys() async -> JWTKeyCollection {
        await JWTKeyCollection.hmac(secret: secret)
    }

    static func token(
        userID: UUID = UUID(),
        expiresIn seconds: TimeInterval = 3600,
        secret: String = TestSupport.secret
    ) async throws -> String {
        let payload = AccessTokenPayload(
            sub: SubjectClaim(value: userID.uuidString),
            exp: ExpirationClaim(value: Date().addingTimeInterval(seconds))
        )
        return try await JWTKeyCollection.hmac(secret: secret).sign(payload)
    }

    static func authHeaders(_ token: String) -> HTTPFields {
        [.authorization: "Bearer \(token)", .contentType: "application/json"]
    }

    static func problem(from response: TestResponse) throws -> ProblemDetails {
        #expect(response.headers[.contentType] == "application/problem+json")
        return try JSONDecoder().decode(ProblemDetails.self, from: response.body)
    }
}

extension ByteBuffer {
    init(json: String) {
        self.init(string: json)
    }
}

extension TestSupport {
    /// 2026-09-26T10:00:00Z, so `today` is 2026-09-26 in every resource test.
    static let now = Date(timeIntervalSince1970: 1_790_416_800)

    static func apiApplication(repositories: Repositories? = nil) async -> some ApplicationProtocol {
        let clock: @Sendable () -> Date = { now }
        let router = buildRouter(
            keys: await keys(),
            repositories: repositories ?? .inMemory(clock: clock),
            clock: clock
        )
        return Application(router: router)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from response: TestResponse) throws -> Value {
        try JSONDecoder.budgetAPI.decode(Value.self, from: response.body)
    }
}

/// Thin helper over `TestClientProtocol` for authenticated JSON calls.
struct APIClient {
    let client: any TestClientProtocol
    let token: String

    func send(_ method: HTTPRequest.Method, _ uri: String, json: String? = nil) async throws -> TestResponse {
        try await client.execute(
            uri: uri,
            method: method,
            headers: TestSupport.authHeaders(token),
            body: json.map { ByteBuffer(json: $0) }
        )
    }
}
