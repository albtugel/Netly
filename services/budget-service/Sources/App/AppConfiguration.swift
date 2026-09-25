import Foundation

struct AppConfiguration: Sendable {
    var hostname: String
    var port: Int

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> AppConfiguration {
        AppConfiguration(
            hostname: "0.0.0.0",
            port: environment["PORT"].flatMap(Int.init) ?? 8082
        )
    }
}
