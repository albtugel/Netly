import Hummingbird

/// A single invalid field reported inside a `validation_failed` error.
struct FieldError: Codable, Equatable, Sendable {
    let field: String
    let code: String
    let message: String
}

/// Error type for every expected failure. `APIErrorMiddleware` renders it as an `ErrorEnvelope`.
struct APIError: Error, Equatable, Sendable {
    let status: HTTPResponse.Status
    let code: String
    let message: String
    var fieldErrors: [FieldError] = []

    static func malformedJSON(_ message: String = "Request body is not valid JSON") -> APIError {
        APIError(status: .badRequest, code: "malformed_json", message: message)
    }

    static func unauthorized(_ message: String) -> APIError {
        APIError(status: .unauthorized, code: "unauthorized", message: message)
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
            status: .unprocessableContent,
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
