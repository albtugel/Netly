import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

@testable import App

private enum Color: String, APIEnum {
    case red, green
}

private struct EchoRequest: Decodable {
    let name: String
    let amount: Decimal
    let date: CalendarDate
    let color: Color
}

/// A router with the production middleware and two probe routes.
private func probeApplication() async -> some ApplicationProtocol {
    let router = buildRouter(keys: await TestSupport.keys())
    router.post("echo") { request, context -> HTTPResponse.Status in
        let input = try await request.decodeJSON(as: EchoRequest.self, context: context)
        var validator = Validator()
        validator.text(input.name, field: "name")
        validator.money(input.amount, field: "amount", maximum: 1_000)
        try validator.throwIfInvalid()
        return .noContent
    }
    router.group("secure")
        .add(middleware: JWTAuthenticator(keys: await TestSupport.keys()))
        .get("me") { _, context in
            try context.requireIdentity().id.uuidString
        }
    router.get("boom") { _, _ -> String in
        throw CancellationError()
    }
    return Application(router: router)
}

@Suite struct ErrorFormatTests {
    @Test func unknownRouteIsProblemNotFound() async throws {
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/nope", method: .get) { response in
                #expect(response.status == .notFound)
                let problem = try TestSupport.problem(from: response)
                #expect(problem.code == "not_found")
                #expect(problem.status == 404)
                #expect(problem.instance == "/nope")
                #expect(problem.errors == nil)
            }
        }
    }

    @Test func malformedJSONIsBadRequest() async throws {
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/echo", method: .post, body: ByteBuffer(json: "{ not json")) { response in
                #expect(response.status == .badRequest)
                let problem = try TestSupport.problem(from: response)
                #expect(problem.code == "malformed_json")
            }
        }
    }

    @Test func missingFieldIsRequired() async throws {
        let body = #"{"amount": 1, "date": "2030-01-01", "color": "red"}"#
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/echo", method: .post, body: ByteBuffer(json: body)) { response in
                #expect(response.status == .unprocessableContent)
                let problem = try TestSupport.problem(from: response)
                #expect(problem.code == "validation_failed")
                #expect(problem.errors == [FieldError(field: "name", code: "required", message: "Field is required")])
            }
        }
    }

    @Test func wrongTypeIsInvalidType() async throws {
        let body = #"{"name": "x", "amount": "ten", "date": "2030-01-01", "color": "red"}"#
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/echo", method: .post, body: ByteBuffer(json: body)) { response in
                let problem = try TestSupport.problem(from: response)
                #expect(problem.errors?.first?.field == "amount")
                #expect(problem.errors?.first?.code == "invalid_type")
            }
        }
    }

    @Test func unknownEnumListsAllowedValues() async throws {
        let body = #"{"name": "x", "amount": 1, "date": "2030-01-01", "color": "blue"}"#
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/echo", method: .post, body: ByteBuffer(json: body)) { response in
                let problem = try TestSupport.problem(from: response)
                #expect(problem.errors == [FieldError(field: "color", code: "invalid_value", message: "Must be one of: red, green")])
            }
        }
    }

    @Test func invalidDateIsInvalidValue() async throws {
        let body = #"{"name": "x", "amount": 1, "date": "2030-02-30", "color": "red"}"#
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/echo", method: .post, body: ByteBuffer(json: body)) { response in
                let problem = try TestSupport.problem(from: response)
                #expect(problem.errors?.first?.field == "date")
                #expect(problem.errors?.first?.code == "invalid_value")
            }
        }
    }

    @Test func validatorReportsEveryInvalidField() async throws {
        let body = #"{"name": "  ", "amount": 1.005, "date": "2030-01-01", "color": "red"}"#
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/echo", method: .post, body: ByteBuffer(json: body)) { response in
                #expect(response.status == .unprocessableContent)
                let problem = try TestSupport.problem(from: response)
                #expect(problem.detail == "2 fields are invalid")
                #expect(problem.errors?.map(\.code) == ["blank", "too_precise"])
            }
        }
    }

    @Test func unexpectedErrorHidesDetails() async throws {
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/boom", method: .get) { response in
                #expect(response.status == .internalServerError)
                let problem = try TestSupport.problem(from: response)
                #expect(problem.code == "internal_error")
                #expect(problem.detail == "An unexpected error occurred")
            }
        }
    }

    @Test func missingTokenIsUnauthorized() async throws {
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/secure/me", method: .get) { response in
                #expect(response.status == .unauthorized)
                let problem = try TestSupport.problem(from: response)
                #expect(problem.code == "unauthorized")
                #expect(problem.detail == "Missing bearer token")
            }
        }
    }

    @Test func expiredTokenIsUnauthorized() async throws {
        let token = try await TestSupport.token(expiresIn: -60)
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/secure/me", method: .get, headers: TestSupport.authHeaders(token)) { response in
                #expect(response.status == .unauthorized)
                let problem = try TestSupport.problem(from: response)
                #expect(problem.detail == "Token has expired")
            }
        }
    }

    @Test func foreignSignatureIsUnauthorized() async throws {
        let token = try await TestSupport.token(secret: "another-secret-that-is-also-32-bytes-long")
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/secure/me", method: .get, headers: TestSupport.authHeaders(token)) { response in
                #expect(response.status == .unauthorized)
                let problem = try TestSupport.problem(from: response)
                #expect(problem.detail == "Invalid token")
            }
        }
    }

    @Test func validTokenExposesUser() async throws {
        let userID = UUID()
        let token = try await TestSupport.token(userID: userID)
        try await probeApplication().test(.router) { client in
            try await client.execute(uri: "/secure/me", method: .get, headers: TestSupport.authHeaders(token)) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == userID.uuidString)
            }
        }
    }
}
