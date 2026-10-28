import Foundation
import JWT
import Testing
import Vapor
import VaporTesting

@testable import App

/// Checks that stop before the database: they run without one.
@Suite struct AccessControlTests {
    @Test func healthReturnsOk() async throws {
        try await TestSupport.withApp { app in
            try await app.testing().test(.GET, "health") { response in
                #expect(response.status == .ok)
                let body = try response.content.decode(HealthResponse.self)
                #expect(body.service == "netly-profile")
            }
        }
    }

    @Test func missingTokenIsUnauthorized() async throws {
        try await TestSupport.withApp { app in
            try await app.testing().test(.GET, "api/v1/users/me") { response in
                #expect(response.status == .unauthorized)
                let problem = try TestSupport.problem(response)
                #expect(problem.detail == "Missing bearer token")
            }
        }
    }

    @Test func tokenSignedWithAnotherSecretIsUnauthorized() async throws {
        let forged = try await TestSupport.token(role: .admin, secret: "another-secret-that-is-32-bytes-long")
        try await TestSupport.withApp { app in
            try await app.testing().test(.GET, "api/v1/admin/users", headers: .bearer(forged)) { response in
                #expect(response.status == .unauthorized)
                let problem = try TestSupport.problem(response)
                #expect(problem.detail == "Invalid token")
            }
        }
    }

    @Test func expiredTokenIsUnauthorized() async throws {
        let expired = try await TestSupport.token(issuedAt: Date().addingTimeInterval(-AccessTokenPayload.lifetime - 1))
        try await TestSupport.withApp { app in
            try await app.testing().test(.GET, "api/v1/users/me", headers: .bearer(expired)) { response in
                #expect(response.status == .unauthorized)
                let problem = try TestSupport.problem(response)
                #expect(problem.detail == "Token has expired")
            }
        }
    }

    @Test func userRoleIsForbiddenFromAdminRoutes() async throws {
        let token = try await TestSupport.token(role: .user)
        try await TestSupport.withApp { app in
            try await app.testing().test(.GET, "api/v1/admin/users", headers: .bearer(token)) { response in
                #expect(response.status == .forbidden)
                let problem = try TestSupport.problem(response)
                #expect(problem.code == "forbidden")
                #expect(problem.detail == "Requires the admin role")
            }
        }
    }

    @Test func registrationValidatesEveryField() async throws {
        try await TestSupport.withApp { app in
            try await app.testing().test(.POST, "api/v1/auth/register", beforeRequest: { request in
                try request.content.encode(["email": "not-an-email", "password": "short"])
            }) { response in
                #expect(response.status == .unprocessableEntity)
                let problem = try TestSupport.problem(response)
                #expect(problem.errors?.map(\.field) == ["email", "password"])
                #expect(problem.errors?.map(\.code) == ["invalid_format", "too_short"])
            }
        }
    }

    @Test func passwordLongerThanBcryptLimitIsRejected() async throws {
        try await TestSupport.withApp { app in
            try await app.testing().test(.POST, "api/v1/auth/register", beforeRequest: { request in
                try request.content.encode(["email": "a@netly.kz", "password": String(repeating: "x", count: 73)])
            }) { response in
                #expect(response.status == .unprocessableEntity)
                let problem = try TestSupport.problem(response)
                #expect(problem.errors?.first?.code == "too_long")
            }
        }
    }

    @Test func missingFieldIsReportedByName() async throws {
        try await TestSupport.withApp { app in
            try await app.testing().test(.POST, "api/v1/auth/register", beforeRequest: { request in
                try request.content.encode(["email": "a@netly.kz"])
            }) { response in
                #expect(response.status == .unprocessableEntity)
                let error = try TestSupport.problem(response).errors?.first
                #expect(error?.field == "password")
                #expect(error?.code == "required")
            }
        }
    }

    @Test func malformedJSONIsBadRequest() async throws {
        try await TestSupport.withApp { app in
            try await app.testing().test(.POST, "api/v1/auth/login", headers: ["Content-Type": "application/json"], body: ByteBuffer(string: "{")) { response in
                #expect(response.status == .badRequest)
                let problem = try TestSupport.problem(response)
                #expect(problem.code == "malformed_json")
            }
        }
    }

    @Test func unknownRouteIsProblemJSON() async throws {
        try await TestSupport.withApp { app in
            try await app.testing().test(.GET, "api/v1/nope") { response in
                #expect(response.status == .notFound)
                let problem = try TestSupport.problem(response)
                #expect(problem.code == "not_found")
            }
        }
    }

    @Test func rejectsShortJWTSecret() {
        #expect(throws: AppConfiguration.InvalidConfiguration.self) {
            try AppConfiguration.fromEnvironment(["DB_HOST": "h", "DB_NAME": "n", "DB_USER": "u", "DB_PASSWORD": "p", "JWT_SECRET": "short"])
        }
    }

    @Test func requiresDatabaseSettings() {
        #expect(throws: AppConfiguration.InvalidConfiguration.self) {
            try AppConfiguration.fromEnvironment([:])
        }
    }
}

/// Registration, login and roles against PostgreSQL. Enabled only when the `DB_*` variables are set.
@Suite(.enabled(if: TestSupport.hasDatabase), .serialized)
struct AccountTests {
    private func register(_ app: Application, email: String = "alibek@netly.kz", password: String = "correct horse", extra: [String: String] = [:]) async throws -> User.Response {
        var body = ["email": email, "password": password]
        body.merge(extra) { $1 }
        var created: User.Response?
        try await app.testing().test(.POST, "api/v1/auth/register", beforeRequest: { request in
            try request.content.encode(body)
        }) { response in
            #expect(response.status == .created)
            #expect(response.headers.first(name: .location) == "/api/v1/users/me")
            created = try response.content.decode(User.Response.self)
        }
        return try #require(created)
    }

    private func login(_ app: Application, email: String = "alibek@netly.kz", password: String = "correct horse") async throws -> AuthController.TokenResponse {
        var token: AuthController.TokenResponse?
        try await app.testing().test(.POST, "api/v1/auth/login", beforeRequest: { request in
            try request.content.encode(["email": email, "password": password])
        }) { response in
            #expect(response.status == .ok)
            token = try response.content.decode(AuthController.TokenResponse.self)
        }
        return try #require(token)
    }

    @Test func registrationStoresOnlyABcryptHash() async throws {
        try await TestSupport.withApp(database: true) { app in
            let user = try await register(app, email: "  Alibek@Netly.KZ ")
            #expect(user.email == "alibek@netly.kz")
            #expect(user.role == .user)

            let stored = try #require(try await User.find(UUID(uuidString: user.id), on: app.db))
            #expect(stored.passwordHash.hasPrefix("$2b$12$"))
            #expect(!stored.passwordHash.contains("correct horse"))
        }
    }

    @Test func roleInRegistrationBodyIsIgnored() async throws {
        try await TestSupport.withApp(database: true) { app in
            let user = try await register(app, extra: ["role": "admin"])
            #expect(user.role == .user)
        }
    }

    @Test func duplicateEmailIsConflictIgnoringCase() async throws {
        try await TestSupport.withApp(database: true) { app in
            _ = try await register(app)
            try await app.testing().test(.POST, "api/v1/auth/register", beforeRequest: { request in
                try request.content.encode(["email": "ALIBEK@netly.kz", "password": "another password"])
            }) { response in
                #expect(response.status == .conflict)
            }
        }
    }

    @Test func loginIssuesAFifteenMinuteTokenWithSubjectAndRole() async throws {
        try await TestSupport.withApp(database: true) { app in
            let user = try await register(app)
            let token = try await login(app)
            #expect(token.tokenType == "Bearer")
            #expect(token.expiresIn == 900)

            let payload = try await app.jwt.keys.verify(token.accessToken, as: AccessTokenPayload.self)
            #expect(payload.sub.value == user.id)
            #expect(payload.role == .user)
            #expect(payload.exp.value.timeIntervalSince(payload.iat.value) == 900)

            try await app.testing().test(.GET, "api/v1/users/me", headers: .bearer(token.accessToken)) { response in
                #expect(response.status == .ok)
                let me = try response.content.decode(User.Response.self)
                #expect(me.id == user.id)
            }
        }
    }

    @Test func wrongPasswordAndUnknownEmailFailTheSameWay() async throws {
        try await TestSupport.withApp(database: true) { app in
            _ = try await register(app)
            var details: [String] = []
            for (email, password) in [("alibek@netly.kz", "wrong password"), ("nobody@netly.kz", "correct horse")] {
                try await app.testing().test(.POST, "api/v1/auth/login", beforeRequest: { request in
                    try request.content.encode(["email": email, "password": password])
                }) { response in
                    #expect(response.status == .unauthorized)
                    details.append(try TestSupport.problem(response).detail)
                }
            }
            #expect(details == ["Invalid email or password", "Invalid email or password"])
        }
    }

    @Test func adminListsUsersAfterPromotion() async throws {
        try await TestSupport.withApp(database: true) { app in
            let admin = try await register(app, email: "admin@netly.kz")
            _ = try await register(app, email: "user@netly.kz")
            let stored = try #require(try await User.find(UUID(uuidString: admin.id), on: app.db))
            stored.role = .admin
            try await stored.save(on: app.db)

            let token = try await login(app, email: "admin@netly.kz")
            try await app.testing().test(.GET, "api/v1/admin/users?limit=1", headers: .bearer(token.accessToken)) { response in
                #expect(response.status == .ok)
                let page = try response.content.decode(AdminController.Page.self)
                #expect(page.total == 2)
                #expect(page.items.count == 1)
                #expect(page.items.first?.email == "admin@netly.kz")
            }
            try await app.testing().test(.GET, "api/v1/admin/users?offset=\(Int.max)", headers: .bearer(token.accessToken)) { response in
                #expect(response.status == .ok)
                let page = try response.content.decode(AdminController.Page.self)
                #expect(page.items.isEmpty)
            }
        }
    }
}
