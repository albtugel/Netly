import Foundation
import PostgresNIO

extension SubscriptionFields: PostgresRecordMapping {
    static let table = "subscriptions"
    static let columns = [
        PostgresColumn(name: "name", type: "text"),
        PostgresColumn(name: "price", type: "numeric"),
        PostgresColumn(name: "billing_cycle", type: "text"),
        PostgresColumn(name: "next_charge_date", type: "date"),
    ]

    func bind(into bindings: inout PostgresBindings) throws {
        try bindings.append(name)
        try bindings.append(price)
        try bindings.append(billingCycle.rawValue)
        try bindings.append(nextChargeDate.description)
    }

    init(cells: PostgresRandomAccessRow) throws {
        self.init(
            name: try cells["name"].decode(String.self),
            price: try cells["price"].decode(Decimal.self),
            billingCycle: try cells.decodeEnum("billing_cycle", as: BillingCycle.self),
            nextChargeDate: try cells.decodeCalendarDate("next_charge_date")
        )
    }
}

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
