import Fluent
import Foundation
import JWT
import SQLKit
import Testing
import Vapor
import VaporTesting

@testable import App

enum TestSupport {
    static let secret = "test-secret-that-is-at-least-32-bytes"

    /// `DB_*` from the environment when set, so the database tests can run; otherwise a placeholder that is never dialled.
    static let databaseEnvironment: [String: String]? = {
        let environment = ProcessInfo.processInfo.environment
        let keys = AppConfiguration.requiredDatabaseVariables + ["DB_PORT"]
        let database = environment.filter { keys.contains($0.key) }
        return AppConfiguration.requiredDatabaseVariables.allSatisfy({ database[$0] != nil }) ? database : nil
    }()

    static var hasDatabase: Bool { databaseEnvironment != nil }

    static func configuration() throws -> AppConfiguration {
        var environment = databaseEnvironment ?? ["DB_HOST": "localhost", "DB_NAME": "unused", "DB_USER": "unused", "DB_PASSWORD": "unused"]
        environment["JWT_SECRET"] = secret
        return try AppConfiguration.fromEnvironment(environment)
    }

    /// A configured application. With `database: true` it is migrated and the `users` table is emptied first;
    /// only the serialized database suite asks for that, so parallel tests never race on the schema.
    static func withApp(database: Bool = false, _ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app, configuration: configuration())
            if database {
                try await app.autoMigrate()
                try await (app.db as! any SQLDatabase).raw("TRUNCATE users").run()
            }
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    static func token(userID: UUID = UUID(), role: Role = .user, issuedAt: Date = Date(), secret: String = secret) async throws -> String {
        let keys = JWTKeyCollection()
        await keys.add(hmac: HMACKey(from: secret), digestAlgorithm: .sha256)
        return try await keys.sign(AccessTokenPayload(userID: userID, role: role, issuedAt: issuedAt))
    }

    /// The `error` object of an error response.
    static func errorBody(_ response: TestingHTTPResponse) throws -> ErrorEnvelope.Body {
        #expect(response.headers.contentType == .json)
        return try JSONDecoder().decode(ErrorEnvelope.self, from: response.body).error
    }
}

extension HTTPHeaders {
    static func bearer(_ token: String) -> HTTPHeaders {
        ["Authorization": "Bearer \(token)"]
    }
}
