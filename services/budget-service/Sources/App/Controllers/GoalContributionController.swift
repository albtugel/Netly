import Foundation
import Hummingbird

/// `POST` and `GET /api/v1/goals/{id}/contributions`: top up a savings goal and list its top-ups.
struct GoalContributionController: Sendable {
    let repository: any GoalContributionRepository
    let clock: @Sendable () -> Date

    func addRoutes(to api: RouterGroup<BudgetRequestContext>) {
        let contributions = api.group("goals/:id/contributions")
        contributions.post(use: create)
        contributions.get(use: list)
    }

    @Sendable func create(_ request: Request, context: BudgetRequestContext) async throws -> EditedResponse<GoalContribution.CreatedResponse> {
        let userID = try context.requireIdentity().id
        let goalID = try context.requireRecordID()
        let input = try await request.decodeJSON(as: GoalContribution.CreateRequest.self, context: context)
        let note = input.note?.trimmed

        var validator = Validator()
        validator.money(input.amount, field: "amount", maximum: GoalFields.maximumAmount)
        if let note {
            validator.text(note, field: "note", maxLength: GoalContribution.maximumNoteLength)
        }
        try validator.throwIfInvalid()

        let result: (contribution: GoalContribution, goal: Record<GoalFields>)?
        do {
            result = try await repository.contribute(goalID: goalID, userID: userID, amount: input.amount, note: note)
        } catch is GoalTargetExceededError {
            throw APIError.validationFailed([
                FieldError(field: "amount", code: "exceeds_target", message: "savedAmount plus amount must not exceed the goal's targetAmount")
            ])
        }
        guard let result else {
            throw Self.goalNotFound(goalID)
        }
        return EditedResponse(
            status: .created,
            response: GoalContribution.CreatedResponse(
                contribution: result.contribution.response,
                goal: GoalFields.response(for: result.goal, today: CalendarDate(clock()))
            )
        )
    }

    @Sendable func list(_ request: Request, context: BudgetRequestContext) async throws -> Page<GoalContribution.Response> {
        let userID = try context.requireIdentity().id
        let goalID = try context.requireRecordID()
        var validator = Validator()
        let pagination = Pagination(request, validator: &validator)
        try validator.throwIfInvalid()

        guard let (records, total) = try await repository.list(goalID: goalID, userID: userID, limit: pagination.limit, offset: pagination.offset) else {
            throw Self.goalNotFound(goalID)
        }
        return Page(items: records.map(\.response), limit: pagination.limit, offset: pagination.offset, total: total)
    }

    private static func goalNotFound(_ id: UUID) -> APIError {
        .notFound("Goal \(id.uuidString.lowercased()) was not found")
    }
}
