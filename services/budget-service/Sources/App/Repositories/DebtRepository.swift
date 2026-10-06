import Foundation
import PostgresNIO

/// Data access for debts: create, read, update, delete and filtered list over the `debts` table.
/// The SQL is shared by `PostgresRecordRepository`; this file maps the resource to its columns.
typealias DebtRepository = PostgresRecordRepository<DebtFields>

extension DebtFields: PostgresRecordMapping {
    static let table = "debts"
    static let columns = [
        PostgresColumn(name: "creditor", type: "text"),
        PostgresColumn(name: "amount", type: "numeric"),
        PostgresColumn(name: "due_date", type: "date"),
    ]

    func bind(into bindings: inout PostgresBindings) throws {
        try bindings.append(creditor)
        try bindings.append(amount)
        try bindings.append(dueDate.description)
    }

    init(cells: PostgresRandomAccessRow) throws {
        self.init(
            creditor: try cells["creditor"].decode(String.self),
            amount: try cells["amount"].decode(Decimal.self),
            dueDate: try cells.decodeCalendarDate("due_date")
        )
    }
}
