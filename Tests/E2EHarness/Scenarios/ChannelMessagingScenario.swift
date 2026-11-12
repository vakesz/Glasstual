import Foundation

/// Join a channel, check the main window's columns, send a message and a
/// reply and see the server's answers in the transcript.
struct ChannelMessagingScenario: Scenario {
	let name = "channelMessaging"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.channelMessaging)
		try await context.exchangeChannelMessages(checkingColumns: true)
		try await context.quit(peerSeesQuit: true)
		try context.requireChannelExchange()
	}
}

extension ScenarioContext {
	/// Connects, joins `#e2e`, sends a message and a reply, and waits for the
	/// peer's answers to both.
	func exchangeChannelMessages(checkingColumns: Bool) async throws {
		try await server(AXID.RowState.disconnected)
		try await connect()
		try await awaitRegistered()
		try await send("/join #e2e")
		try await transcript(contains: "E2E_CHANNEL_READY")
		try await until("#e2e joined and selected") {
			try rowState("channel", "#e2e") == AXID.RowState.joined && isSelected("channel", "#e2e")
		}
		if checkingColumns {
			try await MainWindowColumnsCheck.run(self)
		}
		try await send("E2E_TYPED_MESSAGE")
		try await transcript(contains: "E2E_SERVER_REPLY")
		try await send("fixture: E2E_TYPED_REPLY")
		try await transcript(contains: "E2E_REPLY_ACK")
	}

	func requireChannelExchange() throws {
		let evidence = try requirePeer.evidence
		guard evidence.joined, evidence.messageSeen, evidence.replySeen else {
			throw HarnessFailure.assertion("The peer did not see JOIN, the message and the reply")
		}
		try requireStandardRegistration(attempt: 1)
	}
}
