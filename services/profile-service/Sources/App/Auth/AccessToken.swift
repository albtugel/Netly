import JWT
import Vapor

/// Claims of the access token. Budget Service verifies the same token with the shared secret and reads `sub`.
struct AccessTokenPayload: JWTPayload {
    static let lifetime: TimeInterval = 15 * 60

    var sub: SubjectClaim
    var role: Role
    var iat: IssuedAtClaim
    var exp: ExpirationClaim

    init(userID: UUID, role: Role, issuedAt: Date = Date()) {
        // Whole seconds: NumericDate claims are conventionally integers.
        let issued = Date(timeIntervalSince1970: issuedAt.timeIntervalSince1970.rounded(.down))
        self.sub = SubjectClaim(value: userID.uuidString.lowercased())
        self.role = role
        self.iat = IssuedAtClaim(value: issued)
        self.exp = ExpirationClaim(value: issued.addingTimeInterval(Self.lifetime))
    }

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }
}

/// The caller of an authenticated request, taken from a verified token.
struct AuthenticatedUser: Authenticatable {
    let id: UUID
    let role: Role
}

/// Requires a valid `Authorization: Bearer <jwt>` header and logs the user in for the rest of the chain.
struct AccessTokenAuthenticator: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token else {
            throw APIError.unauthorized("Missing bearer token")
        }
        let payload: AccessTokenPayload
        do {
            payload = try await request.jwt.verify(token, as: AccessTokenPayload.self)
        } catch let error as JWTError where error.errorType == .claimVerificationFailure {
            throw APIError.unauthorized("Token has expired")
        } catch {
            throw APIError.unauthorized("Invalid token")
        }
        guard let userID = UUID(uuidString: payload.sub.value) else {
            throw APIError.unauthorized("Token subject is not a user id")
        }
        request.auth.login(AuthenticatedUser(id: userID, role: payload.role))
        return try await next.respond(to: request)
    }
}

/// Lets the request through only for the given role. Mounted after `AccessTokenAuthenticator`,
/// so a missing token is `401` and a valid token with the wrong role is `403`.
struct RoleGuard: AsyncMiddleware {
    let required: Role

    init(_ required: Role) {
        self.required = required
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let user = try request.auth.require(AuthenticatedUser.self)
        guard user.role == required else {
            throw APIError.forbidden("Requires the \(required.rawValue) role")
        }
        return try await next.respond(to: request)
    }
}
