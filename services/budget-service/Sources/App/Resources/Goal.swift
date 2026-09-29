import Foundation
import Hummingbird

enum GoalStatus: String, APIEnum {
    case active, completed, archived
}

struct GoalFields: ResourceFields {
    static let collectionPath = "goals"
    static let resourceName = "Goal"
    static let maximumAmount: Decimal = 100_000_000
    static let priorities = 1...10

    var name: String
    var targetAmount: Decimal
    var savedAmount: Decimal
    var targetDate: CalendarDate
    /// Higher is more important; the free balance is distributed in descending priority.
    var priority: Int
    var status: GoalStatus

    struct CreateRequest: Decodable, Sendable {
        let name: String
        let targetAmount: Decimal
        let savedAmount: Decimal?
        let targetDate: CalendarDate
        let priority: Int
        let status: GoalStatus?
    }

    struct UpdateRequest: Decodable, Sendable {
        let name: String?
        let targetAmount: Decimal?
        let savedAmount: Decimal?
        let targetDate: CalendarDate?
        let priority: Int?
        let status: GoalStatus?
    }

    struct Response: ResponseCodable, Equatable {
        let id: String
        let name: String
        let targetAmount: Decimal
        let savedAmount: Decimal
        let targetDate: CalendarDate
        let priority: Int
        let status: GoalStatus
        let requiredMonthlyContribution: Decimal
        let createdAt: Date
        let updatedAt: Date
    }

    init(name: String, targetAmount: Decimal, savedAmount: Decimal, targetDate: CalendarDate, priority: Int, status: GoalStatus) {
        self.name = name.trimmed
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.targetDate = targetDate
        self.priority = priority
        self.status = status
    }

    init(_ request: CreateRequest) {
        self.init(
            name: request.name,
            targetAmount: request.targetAmount,
            savedAmount: request.savedAmount ?? 0,
            targetDate: request.targetDate,
            priority: request.priority,
            status: request.status ?? .active
        )
    }

    func applying(_ update: UpdateRequest) -> GoalFields {
        GoalFields(
            name: update.name ?? name,
            targetAmount: update.targetAmount ?? targetAmount,
            savedAmount: update.savedAmount ?? savedAmount,
            targetDate: update.targetDate ?? targetDate,
            priority: update.priority ?? priority,
            status: update.status ?? status
        )
    }

    func validate(into validator: inout Validator, previous: GoalFields?, today: CalendarDate) {
        validator.text(name, field: "name")
        validator.money(targetAmount, field: "targetAmount", maximum: Self.maximumAmount)
        validator.money(savedAmount, field: "savedAmount", allowsZero: true, maximum: Self.maximumAmount)
        if !validator.hasError(for: "savedAmount"), !validator.hasError(for: "targetAmount") {
            validator.check(
                savedAmount <= targetAmount,
                field: "savedAmount",
                code: "exceeds_target",
                message: "Must not exceed targetAmount"
            )
        }
        if targetDate != previous?.targetDate {
            validator.future(targetDate, field: "targetDate", today: today)
        }
        validator.range(priority, field: "priority", Self.priorities)
    }

    /// Monthly amount still needed to reach the target on time; zero once the goal is reached or not active.
    func requiredMonthlyContribution(today: CalendarDate) -> Decimal {
        let remaining = targetAmount - savedAmount
        guard status == .active, remaining > 0 else { return 0 }
        return MonthlyEquivalent.installment(amount: remaining, from: today, until: targetDate)
    }

    static func response(for record: Record<GoalFields>, today: CalendarDate) -> Response {
        let fields = record.fields
        return Response(
            id: record.id.uuidString.lowercased(),
            name: fields.name,
            targetAmount: fields.targetAmount,
            savedAmount: fields.savedAmount,
            targetDate: fields.targetDate,
            priority: fields.priority,
            status: fields.status,
            requiredMonthlyContribution: fields.requiredMonthlyContribution(today: today),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}
