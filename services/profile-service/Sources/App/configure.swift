import Fluent
import FluentPostgresDriver
import JWT
import Vapor

let serviceName = "netly-profile"

struct HealthResponse: Content {
    let status: String
    let service: String
}

func configure(_ app: Application, configuration: AppConfiguration) async throws {
    if configuration.jwtSecret == AppConfiguration.developmentJWTSecret {
        app.logger.warning("JWT_SECRET is the public development secret; set a private one outside local development")
    }

    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = configuration.port

    app.databases.use(.postgres(configuration: configuration.database), as: .psql)
    app.migrations.add(CreateUsers())
    app.asyncCommands.use(MakeAdminCommand(), as: "make-admin")

    await app.jwt.keys.add(hmac: HMACKey(from: configuration.jwtSecret), digestAlgorithm: .sha256)
    // Vapor's default cost for bcrypt is 12; set it explicitly because the defence of the choice depends on it.
    app.passwords.use(.bcrypt(cost: 12))

    // ISO 8601 dates and sorted keys, the same JSON as Budget Service.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Replaces Vapor's ErrorMiddleware so every error leaves the service in the same envelope as Budget Service.
    app.middleware = Middlewares()
    app.middleware.use(APIErrorMiddleware())

    try routes(app)
}

func routes(_ app: Application) throws {
    app.get("health") { _ in
        HealthResponse(status: "ok", service: serviceName)
    }

    let api = app.grouped("api", "v1")
    try api.register(collection: AuthController())

    let authenticated = api.grouped(AccessTokenAuthenticator())
    try authenticated.register(collection: UserController())
    try authenticated.grouped(RoleGuard(.admin)).register(collection: AdminController())
}
