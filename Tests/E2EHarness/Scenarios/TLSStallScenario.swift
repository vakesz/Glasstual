import Foundation

/// A server that accepts TCP and never answers the TLS ClientHello. The
/// application stays responsive while it waits, and Disconnect ends the
/// stalled handshake within five seconds.
struct TLSStallScenario: Scenario {
	let name = "tlsStall"
	let budget = Duration.seconds(90)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.tlsStall)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.until("peer holds the ClientHello unanswered") { peer.evidence.tlsStalled }
		// The handshake is stalled; Settings still opens and closes.
		try await context.openSettings()
		try await context.close(window: AXID.settingsWindow)
		try await context.server(AXID.RowState.disconnected)
		try await context.disconnect()
		try await context.quit(peerSeesQuit: false)
		guard peer.evidence.stallClosed, peer.evidence.registrations.isEmpty, peer.evidence.linesReceived == 0 else {
			throw HarnessFailure.assertion("The stalled connection carried IRC or did not close")
		}
	}
}
