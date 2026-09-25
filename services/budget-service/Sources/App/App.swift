@main
struct App {
    static func main() async throws {
        let app = buildApplication(configuration: .fromEnvironment())
        try await app.runService()
    }
}
