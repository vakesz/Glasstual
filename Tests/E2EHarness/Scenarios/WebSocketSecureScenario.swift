import Foundation

/// IRC over `wss://` to a server whose certificate does not validate: the
/// trust sheet appears as it does for IRC over TLS, and Continue lets the
/// upgrade and the conversation go ahead inside TLS.
struct WebSocketSecureScenario: Scenario {
	let name = "webSocketSecure"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.webSocketSecure)
		try await context.exchangeChannelMessages(checkingColumns: false, acceptingCertificate: true)
		try context.requireSameProcess()
		try await context.quit(peerSeesQuit: true)
		try context.requireChannelExchange()
		guard peer.evidence.connections == 1 else {
			throw HarnessFailure.assertion("Expected one TLS WebSocket connection, saw \(peer.evidence.connections)")
		}
	}
}
