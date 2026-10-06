import Foundation
import Hummingbird
import JWTKit
import Logging
import PostgresNIO

let serviceName = "netly-budget"

struct HealthResponse: ResponseCodable {
    let status: String
    let service: String
}

func makeLogger() -> Logger {
    var logger = Logger(label: serviceName)
    logger.logLevel = .info
    return logger
}

func buildApplication(configuration: AppConfiguration) async throws -> some ApplicationProtocol {
    let logger = makeLogger()
    if configuration.jwtSecret == AppConfiguration.developmentJWTSecret {
        logger.warning("JWT_SECRET is the public development secret; set a private one outside local development")
    }

    let keys = await JWTKeyCollection.hmac(secret: configuration.jwtSecret)

    let postgres = PostgresClient(configuration: configuration.database, backgroundLogger: logger)

    var app = Application(
        router: buildRouter(keys: keys, repositories: .postgres(client: postgres, logger: logger)),
        configuration: .init(
            address: .hostname(configuration.hostname, port: configuration.port),
            serverName: serviceName
        ),
        logger: logger
    )
    app.addServices(postgres)
    app.beforeServerStarts { [logger] in
        try await postgres.logConnection(to: configuration.database, logger: logger)
        try await BudgetMigrations.verify(client: postgres, logger: logger)
    }
    return app
}

func buildRouter(
    keys: JWTKeyCollection,
    repositories: Repositories,
    clock: @escaping @Sendable () -> Date = { Date() }
) -> Router<BudgetRequestContext> {
    let router = Router(context: BudgetRequestContext.self)
    router.add(middleware: ProblemErrorMiddleware())

    router.get("health") { _, _ in
        HealthResponse(status: "ok", service: serviceName)
    }

    let api = router.group("api/v1")
        .add(middleware: JWTAuthenticator(keys: keys))
    ResourceController(repository: repositories.subscriptions, clock: clock).addRoutes(to: api)
    ResourceController(repository: repositories.debts, clock: clock).addRoutes(to: api)
    ResourceController(repository: repositories.goals, clock: clock).addRoutes(to: api)

    return router
}
