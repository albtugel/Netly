import Foundation
import Vapor

/// The body of every error response: `{"error": {"code": …, "message": …, "details": […]}}`, the same as Budget Service.
struct ErrorEnvelope: Codable, Equatable, Sendable {
    struct Body: Codable, Equatable, Sendable {
        let code: String
        let message: String
        /// Every invalid field of a `validation_failed` error; empty for other errors.
        let details: [FieldError]
    }

    let error: Body
}

/// Outermost middleware: every error thrown below it, including Vapor's own (unknown route, wrong content type),
/// leaves the service as an `ErrorEnvelope`. Unexpected errors are logged and never shown to the client.
struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return try Self.response(for: Self.apiError(for: error, request: request))
        }
    }

    static func apiError(for error: any Error, request: Request) -> APIError {
        switch error {
        case let error as APIError:
            return error
        case let error as DecodingError:
            return error.apiError
        case let error as any AbortError:
            switch error.status {
            case .notFound: return .notFound(error.reason)
            case .unauthorized: return .unauthorized(error.reason)
            case .badRequest: return .malformedJSON(error.reason)
            default: return APIError(status: error.status, code: "http_error", message: error.reason)
            }
        default:
            request.logger.error("Unhandled error", metadata: ["error": "\(String(reflecting: error))"])
            return .internalError
        }
    }

    static func response(for error: APIError) throws -> Response {
        let envelope = ErrorEnvelope(error: .init(code: error.code, message: error.message, details: error.fieldErrors))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Response(
            status: error.status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: .init(data: try encoder.encode(envelope))
        )
    }
}
