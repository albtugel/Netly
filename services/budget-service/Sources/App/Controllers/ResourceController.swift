import Foundation
import Hummingbird

/// The five CRUD routes of one resource under `/api/v1/{collectionPath}`.
struct ResourceController<Fields: ResourceFields>: Sendable {
    static var defaultPageSize: Int { 50 }
    static var maximumPageSize: Int { 100 }

    let repository: any RecordRepository<Fields>
    let clock: @Sendable () -> Date

    func addRoutes(to api: RouterGroup<BudgetRequestContext>) {
        let collection = api.group(RouterPath(Fields.collectionPath))
        collection.post(use: create)
        collection.get(use: list)
        collection.get(":id", use: show)
        collection.patch(":id", use: update)
        collection.delete(":id", use: delete)
    }

    @Sendable func create(_ request: Request, context: BudgetRequestContext) async throws -> EditedResponse<Fields.Response> {
        let userID = try context.requireIdentity().id
        let input = try await request.decodeJSON(as: Fields.CreateRequest.self, context: context)
        let fields = Fields(input)
        let today = CalendarDate(clock())
        try validate(fields, previous: nil, today: today)

        let record = try await repository.create(fields, userID: userID)
        return EditedResponse(
            status: .created,
            headers: [.location: "/api/v1/\(Fields.collectionPath)/\(record.id.uuidString.lowercased())"],
            response: Fields.response(for: record, today: today)
        )
    }

    @Sendable func list(_ request: Request, context: BudgetRequestContext) async throws -> Page<Fields.Response> {
        let userID = try context.requireIdentity().id
        let (limit, offset) = try Self.pagination(from: request)
        let (records, total) = try await repository.list(userID: userID, limit: limit, offset: offset)
        let today = CalendarDate(clock())
        return Page(
            items: records.map { Fields.response(for: $0, today: today) },
            limit: limit,
            offset: offset,
            total: total
        )
    }

    @Sendable func show(_ request: Request, context: BudgetRequestContext) async throws -> Fields.Response {
        let userID = try context.requireIdentity().id
        let id = try Self.recordID(from: context)
        guard let record = try await repository.find(id: id, userID: userID) else {
            throw Self.notFound(id)
        }
        return Fields.response(for: record, today: CalendarDate(clock()))
    }

    @Sendable func update(_ request: Request, context: BudgetRequestContext) async throws -> Fields.Response {
        let userID = try context.requireIdentity().id
        let id = try Self.recordID(from: context)
        let patch = try await request.decodeJSON(as: Fields.UpdateRequest.self, context: context)
        guard let existing = try await repository.find(id: id, userID: userID) else {
            throw Self.notFound(id)
        }

        let fields = existing.fields.applying(patch)
        let today = CalendarDate(clock())
        try validate(fields, previous: existing.fields, today: today)

        guard let record = try await repository.update(id: id, userID: userID, fields: fields) else {
            throw Self.notFound(id)
        }
        return Fields.response(for: record, today: today)
    }

    @Sendable func delete(_ request: Request, context: BudgetRequestContext) async throws -> HTTPResponse.Status {
        let userID = try context.requireIdentity().id
        let id = try Self.recordID(from: context)
        guard try await repository.delete(id: id, userID: userID) else {
            throw Self.notFound(id)
        }
        return .noContent
    }

    private func validate(_ fields: Fields, previous: Fields?, today: CalendarDate) throws {
        var validator = Validator()
        fields.validate(into: &validator, previous: previous, today: today)
        try validator.throwIfInvalid()
    }

    private static func recordID(from context: BudgetRequestContext) throws -> UUID {
        guard let raw = context.parameters.get("id"), let id = UUID(uuidString: raw) else {
            throw APIError.validationFailed([FieldError(field: "id", code: "invalid_value", message: "Must be a UUID")])
        }
        return id
    }

    private static func pagination(from request: Request) throws -> (limit: Int, offset: Int) {
        let query = request.uri.queryParameters
        var validator = Validator()
        let limit = integer(query.get("limit"), field: "limit", default: defaultPageSize, validator: &validator)
        let offset = integer(query.get("offset"), field: "offset", default: 0, validator: &validator)
        if let limit {
            validator.range(limit, field: "limit", 1...maximumPageSize)
        }
        if let offset {
            validator.check(offset >= 0, field: "offset", code: "out_of_range", message: "Must be greater than or equal to 0")
        }
        try validator.throwIfInvalid()
        return (limit ?? defaultPageSize, offset ?? 0)
    }

    private static func integer(_ raw: String?, field: String, default defaultValue: Int, validator: inout Validator) -> Int? {
        guard let raw else { return defaultValue }
        guard let value = Int(raw) else {
            validator.add(field: field, code: "invalid_type", message: "Expected integer")
            return nil
        }
        return value
    }

    private static func notFound(_ id: UUID) -> APIError {
        .notFound("\(Fields.resourceName) \(id.uuidString.lowercased()) was not found")
    }
}
