import Foundation
import Vapor

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

/// Outermost middleware: every error thrown below it, including Vapor's own (unknown route, wrong content type),
/// leaves the service as `application/problem+json`. Unexpected errors are logged and never shown to the client.
struct ProblemErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return try Self.response(for: Self.apiError(for: error, request: request), path: request.url.path)
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
            default: return APIError(status: error.status, code: "http_error", title: error.status.reasonPhrase, detail: error.reason)
            }
        default:
            request.logger.error("Unhandled error", metadata: ["error": "\(String(reflecting: error))"])
            return .internalError
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Response(
            status: error.status,
            headers: ["Content-Type": "application/problem+json"],
            body: .init(data: try encoder.encode(problem))
        )
    }
}
