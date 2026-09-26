import Hummingbird
import JWTKit
import Logging

let serviceName = "netly-budget"

struct HealthResponse: ResponseCodable {
    let status: String
    let service: String
}

func buildApplication(configuration: AppConfiguration) async -> some ApplicationProtocol {
    var logger = Logger(label: serviceName)
    logger.logLevel = .info
    if configuration.jwtSecret == AppConfiguration.developmentJWTSecret {
        logger.warning("JWT_SECRET is not set, using the development secret")
    }

    let keys = await JWTKeyCollection.hmac(secret: configuration.jwtSecret)
    let router = buildRouter(keys: keys)

    return Application(
        router: router,
        configuration: .init(
            address: .hostname(configuration.hostname, port: configuration.port),
            serverName: serviceName
        ),
        logger: logger
    )
}

func buildRouter(keys: JWTKeyCollection) -> Router<BudgetRequestContext> {
    let router = Router(context: BudgetRequestContext.self)
    router.add(middleware: ProblemErrorMiddleware())

    router.get("health") { _, _ in
        HealthResponse(status: "ok", service: serviceName)
    }

    return router
}
