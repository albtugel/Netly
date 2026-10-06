import Foundation
import PostgresNIO

/// Data access for goals: create, read, update, delete and filtered list over the `goals` table.
/// The SQL is shared by `PostgresRecordRepository`; this file maps the resource to its columns.
typealias GoalRepository = PostgresRecordRepository<GoalFields>

extension GoalFields: PostgresRecordMapping {
    static let table = "goals"
    static let columns = [
        PostgresColumn(name: "name", type: "text"),
        PostgresColumn(name: "target_amount", type: "numeric"),
        PostgresColumn(name: "saved_amount", type: "numeric"),
        PostgresColumn(name: "target_date", type: "date"),
        PostgresColumn(name: "priority", type: "integer"),
        PostgresColumn(name: "status", type: "text"),
    ]

    func bind(into bindings: inout PostgresBindings) throws {
        try bindings.append(name)
        try bindings.append(targetAmount)
        try bindings.append(savedAmount)
        try bindings.append(targetDate.description)
        try bindings.append(priority)
        try bindings.append(status.rawValue)
    }

    init(cells: PostgresRandomAccessRow) throws {
        self.init(
            name: try cells["name"].decode(String.self),
            targetAmount: try cells["target_amount"].decode(Decimal.self),
            savedAmount: try cells["saved_amount"].decode(Decimal.self),
            targetDate: try cells.decodeCalendarDate("target_date"),
            priority: try cells["priority"].decode(Int.self),
            status: try cells.decodeEnum("status", as: GoalStatus.self)
        )
    }
}
