import Foundation
import Hummingbird

/// The user-editable part of a resource together with its API shapes and rules.
/// `ResourceController` builds the five CRUD routes from this description.
protocol ResourceFields: Sendable, Equatable {
    associatedtype CreateRequest: Decodable & Sendable
    associatedtype UpdateRequest: Decodable & Sendable
    associatedtype Response: ResponseCodable & Equatable

    /// Path segment under `/api/v1`, e.g. `subscriptions`.
    static var collectionPath: String { get }
    /// Human-readable singular name used in error details, e.g. `Subscription`.
    static var resourceName: String { get }

    init(_ request: CreateRequest)

    /// PATCH semantics: absent or `null` fields keep their current value.
    func applying(_ update: UpdateRequest) -> Self

    /// Adds every rule violation to `validator`. `previous` is the stored value on update and `nil` on create,
    /// so rules such as "date must be in the future" only apply to values the client is setting now.
    func validate(into validator: inout Validator, previous: Self?, today: CalendarDate)

    static func response(for record: Record<Self>, today: CalendarDate) -> Response
}

/// A stored resource: its fields plus server-owned metadata.
struct Record<Fields: ResourceFields>: Sendable, Equatable {
    let id: UUID
    let userID: UUID
    var fields: Fields
    let createdAt: Date
    var updatedAt: Date
}

/// One page of a collection.
struct Page<Item: ResponseCodable & Equatable>: ResponseCodable, Equatable {
    let items: [Item]
    let limit: Int
    let offset: Int
    let total: Int
}

/// Trims surrounding whitespace so stored names never start or end with blanks.
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
