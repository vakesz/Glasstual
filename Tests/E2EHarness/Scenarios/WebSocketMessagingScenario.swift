import Foundation

/// IRC over `ws://`: the upgrade, then a channel joined, a message and a
/// reply sent and the server's answers read, each line one text message, and
/// Quit ending with the closing handshake.
struct WebSocketMessagingScenario: Scenario {
	let name = "webSocketMessaging"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.webSocketMessaging)
		try await context.exchangeChannelMessages(checkingColumns: false)
		try await context.quit(peerSeesQuit: true)
		try context.requireChannelExchange()
		guard peer.evidence.connections == 1 else {
			throw HarnessFailure.assertion("Expected one WebSocket connection, saw \(peer.evidence.connections)")
		}
	}
}
