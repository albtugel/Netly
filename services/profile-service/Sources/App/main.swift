import Vapor

let serviceName = "netly-profile"
let servicePort = Environment.get("PORT").flatMap(Int.init) ?? 8081

struct HealthResponse: Content {
    let status: String
    let service: String
}

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)

let app = try await Application.make(env)

app.http.server.configuration.hostname = "0.0.0.0"
app.http.server.configuration.port = servicePort

app.get("health") { _ async -> HealthResponse in
    HealthResponse(status: "ok", service: serviceName)
}

do {
    try await app.execute()
} catch {
    app.logger.report(error: error)
}

try await app.asyncShutdown()
