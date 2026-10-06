import Foundation
import PostgresNIO

/// Data access for subscriptions: create, read, update, delete and filtered list over the `subscriptions` table.
/// The SQL is shared by `PostgresRecordRepository`; this file maps the resource to its columns.
typealias SubscriptionRepository = PostgresRecordRepository<SubscriptionFields>

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
