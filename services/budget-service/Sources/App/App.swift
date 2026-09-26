@main
struct App {
    static func main() async throws {
        let app = await buildApplication(configuration: try .fromEnvironment())
        try await app.runService()
    }
}
