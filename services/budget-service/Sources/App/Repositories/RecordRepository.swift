import Foundation

/// Storage for one resource. Every method is scoped to a user: another user's record behaves as missing.
protocol RecordRepository<Fields>: Sendable {
    associatedtype Fields: ResourceFields

    /// Records matching every filter, ordered by creation time, oldest first, with the total count before paging.
    func list(userID: UUID, filters: [AppliedFilter<Fields>], limit: Int, offset: Int) async throws -> (records: [Record<Fields>], total: Int)
    func find(id: UUID, userID: UUID) async throws -> Record<Fields>?
    /// Throws `DuplicateRecordError` when the record breaks a unique constraint.
    func create(_ fields: Fields, userID: UUID) async throws -> Record<Fields>
    /// Returns `nil` when the record does not exist for this user. Throws `DuplicateRecordError` like `create`.
    func update(id: UUID, userID: UUID, fields: Fields) async throws -> Record<Fields>?
    /// Returns `false` when the record does not exist for this user.
    func delete(id: UUID, userID: UUID) async throws -> Bool
}

/// The database refused a write because a record with the same unique key already exists,
/// e.g. a second subscription with the same name.
struct DuplicateRecordError: Error {}

/// Equality filter a list endpoint accepts as a query parameter, e.g. `GET /goals?status=active`.
struct ListFilter<Fields: ResourceFields>: Sendable {
    /// Query parameter, the same as the API field name.
    let name: String
    /// Table column. It comes from this static definition, never from input.
    let column: String
    let allowedValues: [String]
    /// Reads the field from a record, for storage that filters in memory.
    let value: @Sendable (Fields) -> String
}

/// A filter together with the value the client asked for.
struct AppliedFilter<Fields: ResourceFields>: Sendable {
    let filter: ListFilter<Fields>
    let value: String

    func matches(_ fields: Fields) -> Bool {
        filter.value(fields) == value
    }
}

/// Process-local storage used by tests. Unlike PostgreSQL it does not enforce unique constraints;
/// the integration tests cover those.
actor InMemoryRecordRepository<Fields: ResourceFields>: RecordRepository {
    private var records: [Record<Fields>] = []
    private let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    func list(userID: UUID, filters: [AppliedFilter<Fields>], limit: Int, offset: Int) -> (records: [Record<Fields>], total: Int) {
        let matching = records.filter { record in
            record.userID == userID && filters.allSatisfy { $0.matches(record.fields) }
        }
        return (Array(matching.dropFirst(offset).prefix(limit)), matching.count)
    }

    func find(id: UUID, userID: UUID) -> Record<Fields>? {
        records.first { $0.id == id && $0.userID == userID }
    }

    func create(_ fields: Fields, userID: UUID) -> Record<Fields> {
        let now = clock()
        let record = Record(id: UUID(), userID: userID, fields: fields, createdAt: now, updatedAt: now)
        records.append(record)
        return record
    }

    func update(id: UUID, userID: UUID, fields: Fields) -> Record<Fields>? {
        guard let index = records.firstIndex(where: { $0.id == id && $0.userID == userID }) else { return nil }
        records[index].fields = fields
        records[index].updatedAt = clock()
        return records[index]
    }

    func delete(id: UUID, userID: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id && $0.userID == userID }) else { return false }
        records.remove(at: index)
        return true
    }
}
