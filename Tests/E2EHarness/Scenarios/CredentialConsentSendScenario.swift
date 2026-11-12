import Foundation

/// As ``CredentialConsentDeclineScenario``, but Send Password: the server
/// password goes out as `PASS` before `NICK`, and SASL PLAIN sends the account
/// password once.
struct CredentialConsentSendScenario: Scenario {
	let name = "credentialConsentSend"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		try await context.registerAfterCredentialConsent(.send)
	}
}
