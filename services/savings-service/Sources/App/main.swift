import Foundation
import Hummingbird

let serviceName = "netly-savings"
let servicePort = ProcessInfo.processInfo.environment["PORT"].flatMap(Int.init) ?? 8083

struct HealthResponse: ResponseCodable {
    let status: String
    let service: String
}

let router = Router()

router.get("health") { _, _ -> HealthResponse in
    HealthResponse(status: "ok", service: serviceName)
}

let app = Application(
    router: router,
    configuration: .init(
        address: .hostname("0.0.0.0", port: servicePort),
        serverName: serviceName
    )
)

try await app.runService()
