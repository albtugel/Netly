import PostgresNIO
import Testing

@testable import App

@Suite struct DatabaseURLTests {
    @Test func parsesComposeURL() throws {
        let configuration = try PostgresClient.Configuration(databaseURL: "postgres://netly:p%40ss@postgres:5433/netly_budget")
        #expect(configuration.host == "postgres")
        #expect(configuration.port == 5433)
        #expect(configuration.username == "netly")
        #expect(configuration.password == "p@ss")
        #expect(configuration.database == "netly_budget")
    }

    @Test(arguments: ["mysql://u@h/db", "postgres:///db", "not a url"])
    func rejectsInvalidURL(_ url: String) {
        #expect(throws: AppConfiguration.InvalidConfiguration.self) {
            try PostgresClient.Configuration(databaseURL: url)
        }
    }
}
