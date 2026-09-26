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
