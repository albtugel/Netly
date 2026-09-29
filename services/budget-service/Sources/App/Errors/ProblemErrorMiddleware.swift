import Foundation
import Hummingbird

/// RFC 9457 problem document with the `code` and `errors` extensions.
struct ProblemDetails: Codable, Equatable, Sendable {
    let type: String
    let title: String
    let status: Int
    let code: String
    let detail: String
    let instance: String
    let errors: [FieldError]?
}

/// Outermost middleware: every error thrown below it leaves the service as `application/problem+json`.
struct ProblemErrorMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch {
            let apiError = Self.apiError(for: error, context: context)
            return try Self.response(for: apiError, path: request.uri.path)
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
            return APIError(
                status: error.status,
                code: "http_error",
                title: error.status.reasonPhrase,
                detail: error.body ?? error.status.reasonPhrase
            )
        }
    }

    static func response(for error: APIError, path: String) throws -> Response {
        let problem = ProblemDetails(
            type: "about:blank",
            title: error.title,
            status: Int(error.status.code),
            code: error.code,
            detail: error.detail,
            instance: path,
            errors: error.fieldErrors.isEmpty ? nil : error.fieldErrors
        )
        let body = try JSONEncoder.budgetAPI.encode(problem)
        return Response(
            status: error.status,
            headers: [.contentType: "application/problem+json"],
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: body))
        )
    }
}
