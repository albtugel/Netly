import Fluent
import Vapor

/// `GET /api/v1/users/me`: the account behind the token. Any role.
struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("users", "me", use: me)
    }

    @Sendable func me(_ request: Request) async throws -> User.Response {
        let caller = try request.auth.require(AuthenticatedUser.self)
        guard let user = try await User.find(caller.id, on: request.db) else {
            throw APIError.notFound("User \(caller.id.uuidString.lowercased()) was not found")
        }
        return try user.response()
    }
}

/// `GET /api/v1/admin/users`: every account, for the `admin` role only (`RoleGuard`).
struct AdminController: RouteCollection {
    static let defaultLimit = 50
    static let maximumLimit = 100

    struct Page: Content {
        let items: [User.Response]
        let limit: Int
        let offset: Int
        let total: Int
    }

    func boot(routes: any RoutesBuilder) throws {
        routes.get("admin", "users", use: list)
    }

    @Sendable func list(_ request: Request) async throws -> Page {
        let (limit, offset) = try Self.pagination(request)
        let total = try await User.query(on: request.db).count()
        let users = try await User.query(on: request.db)
            .sort(\.$createdAt)
            .sort(\.$id)
            .range(offset..<(offset + limit))
            .all()
        return Page(items: try users.map { try $0.response() }, limit: limit, offset: offset, total: total)
    }

    /// `?limit=1..100` (default 50) and `?offset=0..` (default 0), as in Budget Service.
    private static func pagination(_ request: Request) throws -> (limit: Int, offset: Int) {
        var errors: [FieldError] = []
        var limit = defaultLimit
        var offset = 0
        if let raw = request.query[String.self, at: "limit"] {
            if let value = Int(raw), (1...maximumLimit).contains(value) {
                limit = value
            } else {
                errors.append(FieldError(field: "limit", code: "out_of_range", message: "Must be an integer between 1 and \(maximumLimit)"))
            }
        }
        if let raw = request.query[String.self, at: "offset"] {
            if let value = Int(raw), value >= 0 {
                offset = value
            } else {
                errors.append(FieldError(field: "offset", code: "out_of_range", message: "Must be an integer greater than or equal to 0"))
            }
        }
        if !errors.isEmpty {
            throw APIError.validationFailed(errors)
        }
        return (limit, offset)
    }
}
