import Hummingbird

/// A single invalid field reported inside a `validation_failed` problem.
struct FieldError: Codable, Equatable, Sendable {
    let field: String
    let code: String
    let message: String
}

/// Error type for every expected failure. `ProblemErrorMiddleware` renders it as `application/problem+json`.
struct APIError: Error, Equatable, Sendable {
    let status: HTTPResponse.Status
    let code: String
    let title: String
    let detail: String
    var fieldErrors: [FieldError] = []

    static func malformedJSON(_ detail: String = "Request body is not valid JSON") -> APIError {
        APIError(status: .badRequest, code: "malformed_json", title: "Malformed JSON", detail: detail)
    }

    static func unauthorized(_ detail: String) -> APIError {
        APIError(status: .unauthorized, code: "unauthorized", title: "Unauthorized", detail: detail)
    }

    static func notFound(_ detail: String) -> APIError {
        APIError(status: .notFound, code: "not_found", title: "Not found", detail: detail)
    }

    static func validationFailed(_ fieldErrors: [FieldError]) -> APIError {
        let noun = fieldErrors.count == 1 ? "field is" : "fields are"
        return APIError(
            status: .unprocessableContent,
            code: "validation_failed",
            title: "Validation failed",
            detail: "\(fieldErrors.count) \(noun) invalid",
            fieldErrors: fieldErrors
        )
    }

    static let internalError = APIError(
        status: .internalServerError,
        code: "internal_error",
        title: "Internal server error",
        detail: "An unexpected error occurred"
    )
}
