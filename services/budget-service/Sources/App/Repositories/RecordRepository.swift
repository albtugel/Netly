import Foundation

/// Storage for one resource. Every method is scoped to a user: another user's record behaves as missing.
protocol RecordRepository<Fields>: Sendable {
    associatedtype Fields: ResourceFields

    /// Records ordered by creation time, oldest first, with the total count before paging.
    func list(userID: UUID, limit: Int, offset: Int) async throws -> (records: [Record<Fields>], total: Int)
    func find(id: UUID, userID: UUID) async throws -> Record<Fields>?
    func create(_ fields: Fields, userID: UUID) async throws -> Record<Fields>
    /// Returns `nil` when the record does not exist for this user.
    func update(id: UUID, userID: UUID, fields: Fields) async throws -> Record<Fields>?
    /// Returns `false` when the record does not exist for this user.
    func delete(id: UUID, userID: UUID) async throws -> Bool
}

/// Process-local storage used by tests and for running the service without a database.
actor InMemoryRecordRepository<Fields: ResourceFields>: RecordRepository {
    private var records: [Record<Fields>] = []
    private let clock: @Sendable () -> Date

    init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    func list(userID: UUID, limit: Int, offset: Int) -> (records: [Record<Fields>], total: Int) {
        let owned = records.filter { $0.userID == userID }
        return (Array(owned.dropFirst(offset).prefix(limit)), owned.count)
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
