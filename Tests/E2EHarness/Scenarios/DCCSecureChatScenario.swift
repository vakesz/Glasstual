import Foundation

/// A passive `DCC SCHAT` from a peer never seen before: accepting it asks
/// about the peer's certificate, Trust and Remember lets the handshake
/// finish, a line goes each way over TLS, and the peer hanging up closes the
/// chat. The sidebar names a direct chat `=nick`.
struct DCCSecureChatScenario: Scenario {
	let name = "dccSecureChat"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.dccSecureChat, passiveDCC: true)
		guard let dcc = peer.dcc else { throw HarnessFailure.setup("The DCC peer did not start") }
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()

		try await context.send("/msg fixture E2E_DCC_OFFER")
		try await context.answerAlert(AXID.dccChatOffer, with: AXID.alertDefault(AXID.dccChatOffer))
		try await context.answerAlert(AXID.dccCertificateFirstUse, with: AXID.alertDefault(AXID.dccCertificateFirstUse))
		try await context.until("the secure chat is connected") {
			try context.rowState("direct-chat", "=fixture") == AXID.RowState.joined
		}
		try await context.selectRow("direct-chat", "=fixture")
		try await context.transcript(contains: DCCFixturePeer.chatGreeting)

		try await context.send(DCCFixturePeer.chatReply)
		try await context.until("the peer read the line and hung up") { dcc.outcome != nil }
		guard dcc.outcomes == [DCCFixturePeer.chatted] else {
			throw HarnessFailure.assertion("The secure chat did not carry a line each way: \(dcc.outcomes)")
		}
		try await context.transcript(contains: DCCFixturePeer.chatReply)
		try await context.until("the chat is closed") {
			try context.rowState("direct-chat", "=fixture") == AXID.RowState.notJoined
		}

		try await context.selectRow("server", ScenarioContext.network)
		try await context.send("/msg fixture E2E_DCC_DONE")
		try await context.until("the peer finished on the same IRC connection") { peer.evidence.interactionStage == 2 }
		try await context.quit(peerSeesQuit: true)
		guard peer.evidence.connections == 1 else {
			throw HarnessFailure.assertion("The chat took more than one IRC connection")
		}
	}
}
