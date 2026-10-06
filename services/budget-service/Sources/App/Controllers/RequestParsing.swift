import Foundation
import Hummingbird

extension BudgetRequestContext {
    /// The `:id` path parameter as a UUID.
    func requireRecordID() throws -> UUID {
        guard let raw = parameters.get("id"), let id = UUID(uuidString: raw) else {
            throw APIError.validationFailed([FieldError(field: "id", code: "invalid_value", message: "Must be a UUID")])
        }
        return id
    }
}

/// `?limit=1..100` (default 50) and `?offset=0..` (default 0) of a list endpoint.
struct Pagination {
    static let defaultLimit = 50
    static let maximumLimit = 100

    var limit = defaultLimit
    var offset = 0

    /// Adds invalid values to `validator`, so they are reported together with the endpoint's other query errors.
    init(_ request: Request, validator: inout Validator) {
        let query = request.uri.queryParameters
        if let limit = Self.integer(query.get("limit"), field: "limit", validator: &validator) {
            validator.range(limit, field: "limit", 1...Self.maximumLimit)
            self.limit = limit
        }
        if let offset = Self.integer(query.get("offset"), field: "offset", validator: &validator) {
            validator.check(offset >= 0, field: "offset", code: "out_of_range", message: "Must be greater than or equal to 0")
            self.offset = offset
        }
    }

    private static func integer(_ raw: String?, field: String, validator: inout Validator) -> Int? {
        guard let raw else { return nil }
        guard let value = Int(raw) else {
            validator.add(field: field, code: "invalid_type", message: "Expected integer")
            return nil
        }
        return value
    }
}
