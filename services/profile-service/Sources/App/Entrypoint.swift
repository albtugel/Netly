import Vapor

/// `App` or `App serve` starts the HTTP server, `App migrate` applies pending migrations,
/// `App migrate --revert` reverts the last batch, `App make-admin <email>` grants the admin role.
@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        do {
            try await configure(app, configuration: .fromEnvironment())
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
