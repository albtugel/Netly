import Foundation
import Hummingbird
import HummingbirdAuth
import JWTKit

/// Claims of the access token issued by Profile Service.
struct AccessTokenPayload: JWTPayload {
    var sub: SubjectClaim
    var exp: ExpirationClaim

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }
}

/// Requires a valid `Authorization: Bearer <jwt>` header and stores the user in the context.
struct JWTAuthenticator<Context: AuthRequestContext<AuthenticatedUser>>: RouterMiddleware {
    let keys: JWTKeyCollection

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        guard let bearer = request.headers.bearer else {
            throw APIError.unauthorized("Missing bearer token")
        }

        let payload: AccessTokenPayload
        do {
            payload = try await keys.verify(bearer.token, as: AccessTokenPayload.self)
        } catch let error as JWTError where error.errorType == .claimVerificationFailure {
            throw APIError.unauthorized("Token has expired")
        } catch {
            throw APIError.unauthorized("Invalid token")
        }

        guard let userID = UUID(uuidString: payload.sub.value) else {
            throw APIError.unauthorized("Token subject is not a user id")
        }

        var context = context
        context.identity = AuthenticatedUser(id: userID)
        return try await next(request, context)
    }
}

extension JWTKeyCollection {
    static func hmac(secret: String) async -> JWTKeyCollection {
        let keys = JWTKeyCollection()
        await keys.add(hmac: HMACKey(from: secret), digestAlgorithm: .sha256)
        return keys
    }
}
