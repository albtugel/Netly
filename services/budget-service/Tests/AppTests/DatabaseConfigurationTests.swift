import PostgresNIO
import Testing

@testable import App

@Suite struct DatabaseConfigurationTests {
    static let composeEnvironment = [
        "DB_HOST": "postgres",
        "DB_PORT": "5433",
        "DB_NAME": "netly_budget",
        "DB_USER": "netly",
        "DB_PASSWORD": "p@ss",
    ]

    @Test func readsEveryConnectionSetting() throws {
        let configuration = try PostgresClient.Configuration.fromEnvironment(Self.composeEnvironment)
        #expect(configuration.host == "postgres")
        #expect(configuration.port == 5433)
        #expect(configuration.username == "netly")
        #expect(configuration.password == "p@ss")
        #expect(configuration.database == "netly_budget")
    }

    @Test func defaultsToStandardPort() throws {
        var environment = Self.composeEnvironment
        environment["DB_PORT"] = nil
        #expect(try PostgresClient.Configuration.fromEnvironment(environment).port == 5432)
    }

    @Test func listsEveryMissingSetting() {
        #expect {
            try PostgresClient.Configuration.fromEnvironment(["DB_HOST": "postgres", "DB_USER": ""])
        } throws: { error in
            "\(error)" == "Database settings are missing: DB_NAME, DB_USER, DB_PASSWORD"
        }
    }

    @Test(arguments: ["abc", "0", "70000"])
    func rejectsInvalidPort(_ port: String) {
        var environment = Self.composeEnvironment
        environment["DB_PORT"] = port
        #expect(throws: AppConfiguration.InvalidConfiguration.self) {
            try PostgresClient.Configuration.fromEnvironment(environment)
        }
    }
}
