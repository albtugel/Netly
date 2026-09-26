import Foundation
import Hummingbird

struct DebtFields: ResourceFields {
    static let collectionPath = "debts"
    static let resourceName = "Debt"
    static let maximumAmount: Decimal = 100_000_000

    var creditor: String
    var amount: Decimal
    var dueDate: CalendarDate

    struct CreateRequest: Decodable, Sendable {
        let creditor: String
        let amount: Decimal
        let dueDate: CalendarDate
    }

    struct UpdateRequest: Decodable, Sendable {
        let creditor: String?
        let amount: Decimal?
        let dueDate: CalendarDate?
    }

    struct Response: ResponseCodable, Equatable {
        let id: String
        let creditor: String
        let amount: Decimal
        let dueDate: CalendarDate
        let monthlyPayment: Decimal
        let createdAt: Date
        let updatedAt: Date
    }

    init(creditor: String, amount: Decimal, dueDate: CalendarDate) {
        self.creditor = creditor.trimmed
        self.amount = amount
        self.dueDate = dueDate
    }

    init(_ request: CreateRequest) {
        self.init(creditor: request.creditor, amount: request.amount, dueDate: request.dueDate)
    }

    func applying(_ update: UpdateRequest) -> DebtFields {
        DebtFields(
            creditor: update.creditor ?? creditor,
            amount: update.amount ?? amount,
            dueDate: update.dueDate ?? dueDate
        )
    }

    func validate(into validator: inout Validator, previous: DebtFields?, today: CalendarDate) {
        validator.text(creditor, field: "creditor")
        validator.money(amount, field: "amount", maximum: Self.maximumAmount)
        if dueDate != previous?.dueDate {
            validator.future(dueDate, field: "dueDate", today: today)
        }
    }

    static func response(for record: Record<DebtFields>, today: CalendarDate) -> Response {
        let fields = record.fields
        return Response(
            id: record.id.uuidString.lowercased(),
            creditor: fields.creditor,
            amount: fields.amount,
            dueDate: fields.dueDate,
            monthlyPayment: MonthlyEquivalent.installment(amount: fields.amount, from: today, until: fields.dueDate),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}
