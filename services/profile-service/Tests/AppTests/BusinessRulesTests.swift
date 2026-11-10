import Foundation
import NIOCore
import Testing
import Vapor

@testable import App

@Suite struct BusinessRulesTests {
    @Test func emailIsTrimmedAndLowercased() {
        #expect(AuthController.normalized("  Alibek@Netly.KZ \n") == "alibek@netly.kz")
    }

    @Test(arguments: [
        ("alibek@netly.kz", true),
        ("a.b+tag@mail.netly.kz", true),
        ("alibek@netly", false),
        ("alibek@@netly.kz", false),
        ("ali bek@netly.kz", false),
        ("@netly.kz", false),
        ("", false),
    ])
    func emailFormat(email: String, isValid: Bool) {
        #expect(AuthController.isValidEmail(email) == isValid)
    }

    @Test func emailLongerThan254CharactersIsInvalid() {
        let local = String(repeating: "a", count: 64)
        let domain = String(repeating: "b", count: 186) + ".kz"
        #expect(AuthController.isValidEmail("\(local)@\(domain)"))
        #expect(!AuthController.isValidEmail("\(local)a@\(domain)"))
    }

    @Test func accessTokenLivesFifteenMinutesAndCarriesSubjectAndRole() {
        let userID = UUID()
        let issuedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let payload = AccessTokenPayload(userID: userID, role: .admin, issuedAt: issuedAt)
        #expect(payload.sub.value == userID.uuidString.lowercased())
        #expect(payload.role == .admin)
        #expect(payload.exp.value.timeIntervalSince(payload.iat.value) == 900)
    }

    @Test func publicAccountShapeHasNoPasswordHash() throws {
        let user = User(email: "alibek@netly.kz", passwordHash: "$2b$12$secret")
        user.id = UUID()
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try user.response())) as? [String: Any]
        #expect(Set(json?.keys.map { $0 } ?? []) == ["id", "email", "role", "createdAt"])
    }

    @Test func validationMessageCountsFields() {
        let field = FieldError(field: "email", code: "invalid_format", message: "Must be an email address")
        #expect(APIError.validationFailed([field]).message == "1 field is invalid")
        #expect(APIError.validationFailed([field, field]).message == "2 fields are invalid")
        #expect(APIError.validationFailed([field]).status == .unprocessableEntity)
    }

    @Test func decodingErrorsMapToFieldCodes() {
        let missing = DecodingError.keyNotFound(
            AnyKey("password"), .init(codingPath: [], debugDescription: "")
        ).apiError
        #expect(missing.fieldErrors == [FieldError(field: "password", code: "required", message: "Field is required")])

        let mistyped = DecodingError.typeMismatch(
            String.self, .init(codingPath: [AnyKey("email")], debugDescription: "")
        ).apiError
        #expect(mistyped.fieldErrors.map(\.code) == ["invalid_type"])

        let unreadable = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")).apiError
        #expect(unreadable.code == "malformed_json")
    }
}

@Suite struct RateLimiterTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_790_000_000)
    }

    @Test func allowsUpToTheLimitThenReportsTheWait() async {
        let clock = Clock()
        let limiter = RateLimiter(limit: 3, window: 60, now: { clock.now })
        for _ in 1...3 {
            #expect(await limiter.acquire("login 10.0.0.1") == nil)
        }
        clock.now += 20
        #expect(await limiter.acquire("login 10.0.0.1") == 40)
    }

    @Test func windowResetsAfterItExpires() async {
        let clock = Clock()
        let limiter = RateLimiter(limit: 1, window: 60, now: { clock.now })
        #expect(await limiter.acquire("login 10.0.0.1") == nil)
        #expect(await limiter.acquire("login 10.0.0.1") != nil)
        clock.now += 60
        #expect(await limiter.acquire("login 10.0.0.1") == nil)
    }

    @Test func fullTableEvictsAClientThatIsNotBlocked() async {
        let clock = Clock()
        let limiter = RateLimiter(limit: 2, window: 60, maximumTrackedKeys: 2, now: { clock.now })
        #expect(await limiter.acquire("login 10.0.0.1") == nil)
        #expect(await limiter.acquire("login 10.0.0.1") == nil)
        clock.now += 1
        #expect(await limiter.acquire("login 10.0.0.2") == nil)
        #expect(await limiter.acquire("login 10.0.0.3") == nil)
        #expect(await limiter.acquire("login 10.0.0.1") != nil)
    }

    @Test func ipv6ClientsShareTheirSlash64() throws {
        let first = try SocketAddress(ipAddress: "2001:db8:1:2:aaaa::1", port: 0)
        let second = try SocketAddress(ipAddress: "2001:db8:1:2:bbbb::2", port: 0)
        let otherNetwork = try SocketAddress(ipAddress: "2001:db8:1:3::1", port: 0)
        #expect(RateLimitMiddleware.clientKey(first) == RateLimitMiddleware.clientKey(second))
        #expect(RateLimitMiddleware.clientKey(first) != RateLimitMiddleware.clientKey(otherNetwork))
        #expect(RateLimitMiddleware.clientKey(try SocketAddress(ipAddress: "10.0.0.1", port: 0)) == "10.0.0.1")
        #expect(RateLimitMiddleware.clientKey(try SocketAddress(ipAddress: "::ffff:10.0.0.2", port: 0)) == "10.0.0.2")
    }

    @Test func clientsAndRoutesAreCountedSeparately() async {
        let limiter = RateLimiter(limit: 1, window: 60)
        #expect(await limiter.acquire("login 10.0.0.1") == nil)
        #expect(await limiter.acquire("login 10.0.0.2") == nil)
        #expect(await limiter.acquire("register 10.0.0.1") == nil)
        #expect(await limiter.acquire("login 10.0.0.1") != nil)
    }
}

private struct AnyKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
