import Fluent
import JWT
import Vapor

/// `POST /api/v1/auth/register` and `POST /api/v1/auth/login`, the two public routes.
struct AuthController: RouteCollection {
    static let minimumPasswordLength = 8
    /// bcrypt ignores everything past 72 bytes; a longer password would silently match its prefix.
    static let maximumPasswordBytes = 72
    static let maximumEmailLength = 254

    /// A hash of a random password. Login verifies against it when the email is unknown,
    /// so both failures take as long as a real check and the response time does not reveal registered emails.
    private static let unknownUserHash = try! Bcrypt.hash(UUID().uuidString, cost: 12)

    struct Credentials: Content {
        let email: String
        let password: String
    }

    struct TokenResponse: Content, Equatable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int
    }

    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)
    }

    /// Only `email` and `password` are read: a `role` in the body is ignored, so nobody can register as admin.
    @Sendable func register(_ request: Request) async throws -> Response {
        let input = try request.content.decode(Credentials.self)
        let email = Self.normalized(input.email)

        var errors: [FieldError] = []
        if !Self.isValidEmail(email) {
            errors.append(FieldError(field: "email", code: "invalid_format", message: "Must be an email address"))
        }
        if input.password.count < Self.minimumPasswordLength {
            errors.append(FieldError(field: "password", code: "too_short", message: "Must be at least \(Self.minimumPasswordLength) characters"))
        } else if input.password.utf8.count > Self.maximumPasswordBytes {
            errors.append(FieldError(field: "password", code: "too_long", message: "Must be at most \(Self.maximumPasswordBytes) bytes"))
        }
        if !errors.isEmpty {
            throw APIError.validationFailed(errors)
        }

        // Hashing runs on a thread pool: bcrypt at cost 12 takes about 0.2 s and would stall the event loop.
        let hash = try await request.password.async.hash(input.password)
        let user = User(email: email, passwordHash: hash)
        do {
            try await user.create(on: request.db)
        } catch let error as any DatabaseError where error.isConstraintFailure {
            throw APIError.conflict("An account with this email already exists")
        }

        let response = Response(status: .created)
        response.headers.replaceOrAdd(name: .location, value: "/api/v1/users/me")
        try response.content.encode(try user.response())
        return response
    }

    @Sendable func login(_ request: Request) async throws -> TokenResponse {
        let input = try request.content.decode(Credentials.self)
        let user = try await User.query(on: request.db)
            .filter(\.$email == Self.normalized(input.email))
            .first()

        let matches = try await request.password.async.verify(input.password, created: user?.passwordHash ?? Self.unknownUserHash)
        guard let user, matches else {
            throw APIError.unauthorized("Invalid email or password")
        }

        let token = try await request.jwt.sign(AccessTokenPayload(userID: try user.requireID(), role: user.role))
        return TokenResponse(accessToken: token, tokenType: "Bearer", expiresIn: Int(AccessTokenPayload.lifetime))
    }

    static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// One `@`, no whitespace, a dot in the domain. Deliverability is not checked here.
    static func isValidEmail(_ email: String) -> Bool {
        email.count <= maximumEmailLength
            && email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
}
