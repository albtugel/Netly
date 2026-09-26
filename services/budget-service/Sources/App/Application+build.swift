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

func buildApplication(configuration: AppConfiguration) async throws -> some ApplicationProtocol {
    var logger = Logger(label: serviceName)
    logger.logLevel = .info
    if configuration.jwtSecret == AppConfiguration.developmentJWTSecret {
        logger.warning("JWT_SECRET is the public development secret; set a private one outside local development")
    }

    let keys = await JWTKeyCollection.hmac(secret: configuration.jwtSecret)

    let postgres: PostgresClient?
    let repositories: Repositories
    if let databaseURL = configuration.databaseURL {
        let client = PostgresClient(configuration: try .init(databaseURL: databaseURL), backgroundLogger: logger)
        postgres = client
        repositories = .postgres(client: client, logger: logger)
    } else {
        logger.warning("DATABASE_URL is not set, data is kept in memory and lost on restart")
        postgres = nil
        repositories = .inMemory()
    }

    var app = Application(
        router: buildRouter(keys: keys, repositories: repositories),
        configuration: .init(
            address: .hostname(configuration.hostname, port: configuration.port),
            serverName: serviceName
        ),
        logger: logger
    )
    if let postgres {
        app.addServices(postgres)
        app.beforeServerStarts { [logger] in
            try await Schema.migrate(client: postgres, logger: logger)
        }
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
