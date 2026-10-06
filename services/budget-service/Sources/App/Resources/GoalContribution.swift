import Foundation
import Hummingbird

/// One top-up of a savings goal. Its amount is added to the goal's `savedAmount` when it is recorded.
struct GoalContribution: Sendable, Equatable {
    static let maximumNoteLength = 200

    let id: UUID
    let goalID: UUID
    let amount: Decimal
    let note: String?
    let createdAt: Date

    struct CreateRequest: Decodable, Sendable {
        let amount: Decimal
        let note: String?
    }

    struct Response: ResponseCodable, Equatable {
        let id: String
        let goalId: String
        let amount: Decimal
        let note: String?
        let createdAt: Date
    }

    /// `POST /goals/{id}/contributions` answers with the new contribution and the goal it changed.
    struct CreatedResponse: ResponseCodable, Equatable {
        let contribution: Response
        let goal: GoalFields.Response
    }

    var response: Response {
        Response(id: id.uuidString.lowercased(), goalId: goalID.uuidString.lowercased(), amount: amount, note: note, createdAt: createdAt)
    }
}
