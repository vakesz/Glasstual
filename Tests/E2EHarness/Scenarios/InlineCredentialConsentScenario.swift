import ApplicationServices
import Foundation

/** With questions shown in the conversation, the password consent for a
 server whose certificate nobody checked is a card above the message field.
 `/yes` does not answer a security question: the refusal spells out the answer
 to type, and typing it sends the passwords. Nothing reaches the peer before
 the answer. */
struct InlineCredentialConsentScenario: Scenario {
	let name = "inlineCredentialConsent"
	let budget = Duration.seconds(180)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.credentialConsentSend)
		try await context.server(AXID.RowState.disconnected)
		try await context.storePasswords()
		try await context.chooseConversationStyle()

		try await context.connect()
		try await context.until("credential consent card in the prompt tray") { try context.consentCardIsShown() }
		try await context.until("TLS connection open") { peer.evidence.connections == 1 }
		try context.requireNothingSent(peer)

		try await context.send("/yes")
		let number = try await context.until("the refusal spells the answer out") { () -> String? in
			guard let feedback = try context.mainWindow().flatMap({ try context.driver.find(AXID.promptFeedback, in: $0) })
			else { return nil }
			let text = try [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
				.compactMap { try context.driver.string(feedback, $0) }.joined(separator: "\n")
			return text.firstMatch(of: /\/answer (\d+) send/).map { String($0.1) }
		}
		try context.requireNothingSent(peer)
		guard try context.consentCardIsShown() else {
			throw HarnessFailure.assertion("/yes answered the consent question")
		}

		try await context.send("/answer \(number) send")
		try await context.awaitRegistered()
		let expected = SASLConsentFixture(answer: .send).expectedEvidence
		guard peer.evidence.consent == expected else {
			throw HarnessFailure.assertion("Consent evidence was \(peer.evidence.consent ?? "missing"), expected \(expected)")
		}
		try await context.quit(peerSeesQuit: true)
	}
}

private extension ScenarioContext {
	/// Settings > General: questions appear in the conversation.
	func chooseConversationStyle() async throws {
		try await openSettings()
		try await selectSettingsPage("general")
		try await choose(
			AXID.settingsInteractionStyle("conversation"),
			fromMenu: AXID.settingsInteractionStyle,
			inWindow: AXID.settingsWindow
		)
		try await storedSetting(SettingsKey.interactionStyle, "is the conversation style") {
			($0 as? NSNumber)?.intValue == 1
		}
		try await close(window: AXID.settingsWindow)
	}

	/// Whether the tray shows the consent card, known by its Send button,
	/// which keeps the alert's identifier as a card.
	func consentCardIsShown() throws -> Bool {
		guard let tray = try mainWindow().flatMap({ try driver.find(AXID.promptTray, in: $0) }) else { return false }
		return try driver.find(AXID.alertAlternate(AXID.credentialConsent), in: tray) != nil
	}

	func requireNothingSent(_ peer: LoopbackPeer) throws {
		guard peer.evidence.linesReceived == 0 else {
			throw HarnessFailure.assertion(
				"\(peer.evidence.linesReceived) lines reached the peer before the consent question was answered"
			)
		}
	}
}
