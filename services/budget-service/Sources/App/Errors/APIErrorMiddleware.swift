import Foundation
import Hummingbird

/// The body of every error response: `{"error": {"code": …, "message": …, "details": […]}}`.
struct ErrorEnvelope: Codable, Equatable, Sendable {
    struct Body: Codable, Equatable, Sendable {
        let code: String
        let message: String
        /// Every invalid field of a `validation_failed` error; empty for other errors.
        let details: [FieldError]
    }

    let error: Body
}

/// Outermost middleware: every error thrown below it leaves the service as an `ErrorEnvelope`.
/// Unexpected errors are logged and answered with `internal_error`, never with their description.
struct APIErrorMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch {
            return try Self.response(for: Self.apiError(for: error, context: context))
        }
    }

    static func apiError(for error: any Error, context: Context) -> APIError {
        switch error {
        case let error as APIError:
            return error
        case let error as DecodingError:
            return error.apiError
        case let error as HTTPError:
            return apiError(for: error)
        default:
            context.logger.error("Unhandled error", metadata: ["error": "\(String(reflecting: error))"])
            return .internalError
        }
    }

    private static func apiError(for error: HTTPError) -> APIError {
        switch error.status {
        case .notFound:
            return .notFound(error.body ?? "Route not found")
        case .unauthorized:
            return .unauthorized(error.body ?? "Authentication required")
        case .badRequest:
            return .malformedJSON(error.body ?? "Bad request")
        default:
            return APIError(status: error.status, code: "http_error", message: error.body ?? error.status.reasonPhrase)
        }
    }

    static func response(for error: APIError) throws -> Response {
        let envelope = ErrorEnvelope(error: .init(code: error.code, message: error.message, details: error.fieldErrors))
        let body = try JSONEncoder.budgetAPI.encode(envelope)
        return Response(
            status: error.status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: body))
        )
    }
}
