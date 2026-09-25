import Hummingbird
import Logging

let serviceName = "netly-budget"

struct HealthResponse: ResponseCodable {
    let status: String
    let service: String
}

func buildApplication(configuration: AppConfiguration) -> some ApplicationProtocol {
    var logger = Logger(label: serviceName)
    logger.logLevel = .info

    let router = Router()
    router.get("health") { _, _ in
        HealthResponse(status: "ok", service: serviceName)
    }

    return Application(
        router: router,
        configuration: .init(
            address: .hostname(configuration.hostname, port: configuration.port),
            serverName: serviceName
        ),
        logger: logger
    )
}
