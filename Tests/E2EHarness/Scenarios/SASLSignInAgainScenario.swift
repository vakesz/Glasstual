import ApplicationServices
import Foundation

/// The mechanism chosen in Server Properties is the one SASL uses, and the
/// only one where the user says so. The server refuses it during registration,
/// which completes signed out; Sign In Again then runs the exchange on the
/// registered connection and succeeds.
struct SASLSignInAgainScenario: Scenario {
	let name = "saslSignInAgain"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.saslSignInAgain)
		try await context.server(AXID.RowState.disconnected)
		try await context.chooseSASLMechanism("PLAIN")
		try await context.connect()
		try await context.awaitRegistered()
		// The server offered SCRAM first; only PLAIN was tried, once.
		try await context.scriptedEvidence("attempts=1 signedIn=false")

		try await context.driver.menu("signInAgainWithSASL")
		try await context.driver.button(AXID.saslSignInSubmit)
		try await context.until("Sign In Again reports success") {
			if try context.driver.anywhere(AXID.saslSignInFailed) != nil {
				throw HarnessFailure.assertion("Sign In Again reported a failure")
			}
			return try context.driver.anywhere(AXID.saslSignInSucceeded) != nil
		}
		try await context.scriptedEvidence(SASLSignInFixture.expectedEvidence)
		try await context.driver.button(AXID.saslSignInSubmit)
		try await context.until("Done closes the sheet") { try context.driver.anywhere(AXID.saslSignInSubmit) == nil }
		try await context.quit(peerSeesQuit: true)
	}
}

private extension ScenarioContext {
	/// Stores the account password and makes `mechanism` the one, and only,
	/// SASL mechanism, through the Identity pane of Server Properties.
	func chooseSASLMechanism(_ mechanism: String) async throws {
		try await openServerProperties()
		try await driver.select(AXID.serverPropertiesPane("identity")) { try self.driver.window(AXID.serverProperties) }
		try await driver.fill(AXID.nicknamePassword, inWindow: AXID.serverProperties, with: SASLConsentFixture.secret, secure: true)
		try await driver.toggle(AXID.serverSASLEnabled, inWindow: AXID.serverProperties, to: true)
		try await choose(AXID.serverSASLMechanism(mechanism), fromMenu: AXID.serverSASLMechanism, inWindow: AXID.serverProperties)
		try await driver.toggle(AXID.serverSASLMechanismOnly, inWindow: AXID.serverProperties, to: true)
		try await requireServerPropertiesEdited(true)
		try await driver.button(AXID.serverPropertiesSave, inWindow: AXID.serverProperties)
		try await requireServerPropertiesEdited(false)
		try await close(window: AXID.serverProperties)
	}
}
