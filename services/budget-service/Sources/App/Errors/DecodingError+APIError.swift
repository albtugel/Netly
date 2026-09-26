import Foundation

extension DecodingError {
    /// Maps a JSON decoding failure to the public error format.
    /// An unreadable body is `400 malformed_json`; a readable body with a bad field is `422 validation_failed`.
    var apiError: APIError {
        switch self {
        case .keyNotFound(let key, let context):
            return .validationFailed([
                FieldError(field: Self.fieldPath(context.codingPath + [key]), code: "required", message: "Field is required")
            ])
        case .valueNotFound(_, let context):
            return .validationFailed([
                FieldError(field: Self.fieldPath(context.codingPath), code: "required", message: "Must not be null")
            ])
        case .typeMismatch(let type, let context):
            return .validationFailed([
                FieldError(
                    field: Self.fieldPath(context.codingPath),
                    code: "invalid_type",
                    message: "Expected \(Self.jsonTypeName(type))"
                )
            ])
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            return .malformedJSON()
        case .dataCorrupted(let context):
            return .validationFailed([
                FieldError(field: Self.fieldPath(context.codingPath), code: "invalid_value", message: context.debugDescription)
            ])
        @unknown default:
            return .malformedJSON()
        }
    }

    private static func fieldPath(_ codingPath: [any CodingKey]) -> String {
        codingPath.reduce(into: "") { path, key in
            if let index = key.intValue {
                path += "[\(index)]"
            } else {
                path += path.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }

    private static func jsonTypeName(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "string"
        case is Int.Type: "integer"
        case is Decimal.Type, is Double.Type: "number"
        case is Bool.Type: "boolean"
        default: "\(type)"
        }
    }
}
