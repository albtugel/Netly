import Foundation
import Hummingbird
import HummingbirdAuth

struct AuthenticatedUser: Sendable {
    let id: UUID
}

struct BudgetRequestContext: AuthRequestContext, RequestContext {
    var coreContext: CoreRequestContextStorage
    var identity: AuthenticatedUser?

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.identity = nil
    }

    var requestDecoder: JSONDecoder { .budgetAPI }
    var responseEncoder: JSONEncoder { .budgetAPI }
}

extension JSONDecoder {
    static var budgetAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var budgetAPI: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension Request {
    /// Decodes the JSON body and lets `DecodingError` reach `ProblemErrorMiddleware` unchanged,
    /// so a bad field becomes `422` with its name instead of a generic `400`.
    func decodeJSON<Value: Decodable>(as type: Value.Type, context: some RequestContext) async throws -> Value {
        let buffer = try await body.collect(upTo: context.maxUploadSize)
        return try JSONDecoder.budgetAPI.decode(Value.self, from: Data(buffer: buffer))
    }
}
