import Foundation
import Vapor

/// A single invalid field reported inside a `validation_failed` error.
struct FieldError: Codable, Equatable, Sendable {
    let field: String
    let code: String
    let message: String
}

/// Error type for every expected failure. `APIErrorMiddleware` renders it as an `ErrorEnvelope`,
/// in the same shape as Budget Service.
struct APIError: Error, Equatable, Sendable {
    let status: HTTPResponseStatus
    let code: String
    let message: String
    var fieldErrors: [FieldError] = []

    static func malformedJSON(_ message: String = "Request body is not valid JSON") -> APIError {
        APIError(status: .badRequest, code: "malformed_json", message: message)
    }

    static func unauthorized(_ message: String) -> APIError {
        APIError(status: .unauthorized, code: "unauthorized", message: message)
    }

    static func forbidden(_ message: String) -> APIError {
        APIError(status: .forbidden, code: "forbidden", message: message)
    }

    static func notFound(_ message: String) -> APIError {
        APIError(status: .notFound, code: "not_found", message: message)
    }

    static func conflict(_ message: String) -> APIError {
        APIError(status: .conflict, code: "conflict", message: message)
    }

    static func validationFailed(_ fieldErrors: [FieldError]) -> APIError {
        let noun = fieldErrors.count == 1 ? "field is" : "fields are"
        return APIError(
            status: .unprocessableEntity,
            code: "validation_failed",
            message: "\(fieldErrors.count) \(noun) invalid",
            fieldErrors: fieldErrors
        )
    }

    static let internalError = APIError(
        status: .internalServerError,
        code: "internal_error",
        message: "An unexpected error occurred"
    )
}

extension DecodingError {
    /// An unreadable body is `400 malformed_json`; a readable body with a missing or mistyped field is `422`.
    var apiError: APIError {
        switch self {
        case .keyNotFound(let key, _):
            return .validationFailed([FieldError(field: key.stringValue, code: "required", message: "Field is required")])
        case .valueNotFound(_, let context):
            return .validationFailed([FieldError(field: Self.field(context), code: "required", message: "Must not be null")])
        case .typeMismatch(_, let context) where !context.codingPath.isEmpty:
            return .validationFailed([FieldError(field: Self.field(context), code: "invalid_type", message: "Has the wrong type")])
        default:
            return .malformedJSON()
        }
    }

    private static func field(_ context: Context) -> String {
        context.codingPath.map(\.stringValue).joined(separator: ".")
    }
}
