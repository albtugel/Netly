import Foundation
import Logging
import PostgresNIO

/// One editable column of a resource table.
struct PostgresColumn: Sendable {
    let name: String
    /// SQL type the bound value is cast to, e.g. `date` for values bound as `YYYY-MM-DD` text.
    let type: String

    var selectExpression: String {
        type == "date" ? "\(name)::text AS \(name)" : name
    }
}

/// How a resource's fields map to its table. Column order must match the order of `bind(into:)`.
protocol PostgresRecordMapping: ResourceFields {
    static var table: String { get }
    static var columns: [PostgresColumn] { get }

    func bind(into bindings: inout PostgresBindings) throws
    init(cells: PostgresRandomAccessRow) throws
}

/// PostgreSQL storage shared by every resource. Identifiers come from the static mapping, never from input;
/// every value is a bound parameter.
struct PostgresRecordRepository<Fields: PostgresRecordMapping>: RecordRepository {
    let client: PostgresClient
    let logger: Logger

    private static var selectList: String {
        (["id", "user_id", "created_at", "updated_at"] + Fields.columns.map(\.selectExpression)).joined(separator: ", ")
    }

    func list(userID: UUID, limit: Int, offset: Int) async throws -> (records: [Record<Fields>], total: Int) {
        var bindings = PostgresBindings()
        try bindings.append(userID)
        try bindings.append(limit)
        try bindings.append(offset)
        let records = try await fetch(
            "SELECT \(Self.selectList) FROM \(Fields.table) WHERE user_id = $1 ORDER BY created_at, id LIMIT $2 OFFSET $3",
            bindings
        )

        var countBindings = PostgresBindings()
        try countBindings.append(userID)
        let rows = try await client.query(
            PostgresQuery(unsafeSQL: "SELECT COUNT(*) FROM \(Fields.table) WHERE user_id = $1", binds: countBindings),
            logger: logger
        )
        var total = 0
        for try await (count) in rows.decode(Int.self) {
            total = count
        }
        return (records, total)
    }

    func find(id: UUID, userID: UUID) async throws -> Record<Fields>? {
        var bindings = PostgresBindings()
        try bindings.append(id)
        try bindings.append(userID)
        return try await fetch(
            "SELECT \(Self.selectList) FROM \(Fields.table) WHERE id = $1 AND user_id = $2",
            bindings
        ).first
    }

    func create(_ fields: Fields, userID: UUID) async throws -> Record<Fields> {
        var bindings = PostgresBindings()
        try bindings.append(UUID())
        try bindings.append(userID)
        try fields.bind(into: &bindings)
        let names = (["id", "user_id"] + Fields.columns.map(\.name)).joined(separator: ", ")
        let values = (["$1", "$2"] + Self.columnPlaceholders(startingAt: 3)).joined(separator: ", ")
        let records = try await fetch(
            "INSERT INTO \(Fields.table) (\(names)) VALUES (\(values)) RETURNING \(Self.selectList)",
            bindings
        )
        guard let record = records.first else {
            throw PostgresRepositoryError.missingReturnedRow(table: Fields.table)
        }
        return record
    }

    func update(id: UUID, userID: UUID, fields: Fields) async throws -> Record<Fields>? {
        var bindings = PostgresBindings()
        try bindings.append(id)
        try bindings.append(userID)
        try fields.bind(into: &bindings)
        let assignments = zip(Fields.columns, Self.columnPlaceholders(startingAt: 3))
            .map { column, placeholder in "\(column.name) = \(placeholder)" }
            .joined(separator: ", ")
        return try await fetch(
            "UPDATE \(Fields.table) SET \(assignments), updated_at = now() WHERE id = $1 AND user_id = $2 RETURNING \(Self.selectList)",
            bindings
        ).first
    }

    func delete(id: UUID, userID: UUID) async throws -> Bool {
        var bindings = PostgresBindings()
        try bindings.append(id)
        try bindings.append(userID)
        let rows = try await client.query(
            PostgresQuery(unsafeSQL: "DELETE FROM \(Fields.table) WHERE id = $1 AND user_id = $2 RETURNING id", binds: bindings),
            logger: logger
        )
        for try await _ in rows {
            return true
        }
        return false
    }

    private static func columnPlaceholders(startingAt first: Int) -> [String] {
        Fields.columns.enumerated().map { offset, column in "$\(first + offset)::\(column.type)" }
    }

    private func fetch(_ sql: String, _ bindings: PostgresBindings) async throws -> [Record<Fields>] {
        let rows = try await client.query(PostgresQuery(unsafeSQL: sql, binds: bindings), logger: logger)
        var records: [Record<Fields>] = []
        for try await row in rows {
            let cells = row.makeRandomAccess()
            records.append(
                Record(
                    id: try cells["id"].decode(UUID.self),
                    userID: try cells["user_id"].decode(UUID.self),
                    fields: try Fields(cells: cells),
                    createdAt: try cells["created_at"].decode(Date.self),
                    updatedAt: try cells["updated_at"].decode(Date.self)
                )
            )
        }
        return records
    }
}

enum PostgresRepositoryError: Error {
    case missingReturnedRow(table: String)
    case invalidStoredValue(column: String, value: String)
}

extension PostgresRandomAccessRow {
    func decodeCalendarDate(_ column: String) throws -> CalendarDate {
        let raw = try self[column].decode(String.self)
        guard let date = CalendarDate(raw) else {
            throw PostgresRepositoryError.invalidStoredValue(column: column, value: raw)
        }
        return date
    }

    func decodeEnum<Value: APIEnum>(_ column: String, as type: Value.Type) throws -> Value {
        let raw = try self[column].decode(String.self)
        guard let value = Value(rawValue: raw) else {
            throw PostgresRepositoryError.invalidStoredValue(column: column, value: raw)
        }
        return value
    }
}
