@main
struct App {
    static func main() async throws {
        let app = try await buildApplication(configuration: .fromEnvironment())
        try await app.runService()
    }
}
