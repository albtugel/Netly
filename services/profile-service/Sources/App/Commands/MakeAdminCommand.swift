import Fluent
import Vapor

/// `App make-admin <email>`: the only way to grant the admin role. The API never accepts a role from a client.
struct MakeAdminCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "email", help: "Email of an existing account")
        var email: String
    }

    var help: String { "Grants the admin role to an existing account" }

    func run(using context: CommandContext, signature: Signature) async throws {
        let email = AuthController.normalized(signature.email)
        guard let user = try await User.query(on: context.application.db).filter(\.$email == email).first() else {
            throw AppConfiguration.InvalidConfiguration(description: "No account with email \(email)")
        }
        user.role = .admin
        try await user.save(on: context.application.db)
        context.console.info("\(email) is now admin; tokens issued from the next login carry the new role")
    }
}
