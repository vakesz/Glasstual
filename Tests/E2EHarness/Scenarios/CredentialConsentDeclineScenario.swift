import ApplicationServices
import Foundation

/// A server whose certificate the network is set not to check: before any
/// line goes out the application asks whether to send the passwords, and Don't
/// Send registers with neither the server password nor SASL.
struct CredentialConsentDeclineScenario: Scenario {
	let name = "credentialConsentDecline"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		try await context.registerAfterCredentialConsent(.decline)
	}
}

extension ScenarioContext {
	/** Stores both synthetic passwords through Server Properties, connects,
	 checks that the peer has received nothing while the consent question is up,
	 answers it and checks what reached the peer afterwards. */
	func registerAfterCredentialConsent(_ answer: SASLConsentFixture.Answer) async throws {
		let mode: FixtureMode = answer == .send ? .credentialConsentSend : .credentialConsentDecline
		let peer = try await launchAgainstPeer(mode)
		try await server(AXID.RowState.disconnected)
		try await storePasswords()
		try await connect()
		let alert = try await until("credential consent alert") { try driver.window(AXID.credentialConsent) }
		try await until("TLS connection open") { peer.evidence.connections == 1 }
		guard peer.evidence.linesReceived == 0 else {
			throw HarnessFailure.assertion(
				"\(peer.evidence.linesReceived) lines reached the peer before the user answered the consent question"
			)
		}
		let button = answer == .send ? AXID.alertAlternate(AXID.credentialConsent) : AXID.alertDefault(AXID.credentialConsent)
		try await driver.press("answer the consent question") { try driver.find(button, in: alert) }
		try await awaitRegistered()
		let expected = SASLConsentFixture(answer: answer).expectedEvidence
		guard peer.evidence.consent == expected else {
			throw HarnessFailure.assertion("Consent evidence was \(peer.evidence.consent ?? "missing"), expected \(expected)")
		}
		try await quit(peerSeesQuit: true)
	}

	/// The application stores secrets in its own keychain items, which the
	/// harness cannot write: they go in through Server Properties.
	func storePasswords() async throws {
		try await driver.menu("serverProperties")
		try await until("Server Properties window") { try driver.window(AXID.serverProperties) != nil }
		let window = { () throws -> AXUIElement? in try self.driver.window(AXID.serverProperties) }
		try await driver.select(AXID.serverPropertiesPane("general"), in: window)
		try await fillSecure(AXID.serverPassword, with: SASLConsentFixture.serverSecret)
		try await driver.select(AXID.serverPropertiesPane("identity"), in: window)
		try await fillSecure(AXID.nicknamePassword, with: SASLConsentFixture.secret)
		try await requireServerPropertiesEdited(true)
		try await driver.button(AXID.serverPropertiesSave, inWindow: AXID.serverProperties)
		/* Save keeps an existing server's window open, as a saved document's
		 is, with nothing left to revert; closing it then asks nothing. */
		try await requireServerPropertiesEdited(false)
		try await close(window: AXID.serverProperties)
	}

	/// Enters a secret in a secure field of the Server Properties window. A
	/// secure field's value cannot be read back, so the peer's evidence is what
	/// checks it.
	private func fillSecure(_ identifier: String, with secret: String) async throws {
		try await driver.fill(identifier, with: secret, secure: true) { try self.driver.window(AXID.serverProperties) }
	}
}
