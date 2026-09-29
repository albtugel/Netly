import Foundation
import Hummingbird

enum BillingCycle: String, APIEnum {
    case weekly, monthly, quarterly, yearly
}

struct SubscriptionFields: ResourceFields {
    static let collectionPath = "subscriptions"
    static let resourceName = "Subscription"
    static let maximumPrice: Decimal = 1_000_000

    var name: String
    var price: Decimal
    var billingCycle: BillingCycle
    var nextChargeDate: CalendarDate

    struct CreateRequest: Decodable, Sendable {
        let name: String
        let price: Decimal
        let billingCycle: BillingCycle
        let nextChargeDate: CalendarDate
    }

    struct UpdateRequest: Decodable, Sendable {
        let name: String?
        let price: Decimal?
        let billingCycle: BillingCycle?
        let nextChargeDate: CalendarDate?
    }

    struct Response: ResponseCodable, Equatable {
        let id: String
        let name: String
        let price: Decimal
        let billingCycle: BillingCycle
        let nextChargeDate: CalendarDate
        let monthlyCost: Decimal
        let createdAt: Date
        let updatedAt: Date
    }

    init(name: String, price: Decimal, billingCycle: BillingCycle, nextChargeDate: CalendarDate) {
        self.name = name.trimmed
        self.price = price
        self.billingCycle = billingCycle
        self.nextChargeDate = nextChargeDate
    }

    init(_ request: CreateRequest) {
        self.init(
            name: request.name,
            price: request.price,
            billingCycle: request.billingCycle,
            nextChargeDate: request.nextChargeDate
        )
    }

    func applying(_ update: UpdateRequest) -> SubscriptionFields {
        SubscriptionFields(
            name: update.name ?? name,
            price: update.price ?? price,
            billingCycle: update.billingCycle ?? billingCycle,
            nextChargeDate: update.nextChargeDate ?? nextChargeDate
        )
    }

    func validate(into validator: inout Validator, previous: SubscriptionFields?, today: CalendarDate) {
        validator.text(name, field: "name")
        validator.money(price, field: "price", maximum: Self.maximumPrice)
    }

    static func response(for record: Record<SubscriptionFields>, today: CalendarDate) -> Response {
        let fields = record.fields
        return Response(
            id: record.id.uuidString.lowercased(),
            name: fields.name,
            price: fields.price,
            billingCycle: fields.billingCycle,
            nextChargeDate: fields.nextChargeDate,
            monthlyCost: MonthlyEquivalent.subscriptionCost(price: fields.price, cycle: fields.billingCycle),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}
