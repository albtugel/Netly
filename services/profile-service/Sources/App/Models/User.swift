import Fluent
import Vapor

enum Role: String, Codable, CaseIterable, Sendable {
    /// Every account registers as `user`; only `App make-admin` grants `admin`.
    case user, admin
}

final class User: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    /// Stored trimmed and lowercased, so the unique constraint is case-insensitive.
    @Field(key: "email") var email: String
    /// bcrypt hash (`$2b$12$…`), never the password itself.
    @Field(key: "password_hash") var passwordHash: String
    @Field(key: "role") var role: Role
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(email: String, passwordHash: String, role: Role = .user) {
        self.email = email
        self.passwordHash = passwordHash
        self.role = role
    }

    /// Public shape of an account: no password hash.
    struct Response: Content, Equatable {
        /// Lowercase, like every id Budget Service returns.
        let id: String
        let email: String
        let role: Role
        let createdAt: Date
    }

    func response() throws -> Response {
        Response(id: try requireID().uuidString.lowercased(), email: email, role: role, createdAt: createdAt ?? Date())
    }
}
