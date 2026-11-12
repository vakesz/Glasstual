import Foundation

/// Cancel on the trust sheet closes the TLS connection before any IRC line;
/// Connect again and Continue registers.
struct TLSRejectRetryScenario: Scenario {
	let name = "tlsRejectRetry"
	let budget = Duration.seconds(90)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.tlsRejectRetry)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.answerCertificate(continue: false)
		try await context.server(AXID.RowState.disconnected)
		try await context.until("peer saw the rejected connection close without IRC") { peer.evidence.tlsRejected }
		try await context.connect()
		try await context.answerCertificate(continue: true)
		try await context.awaitRegistered()
		try context.requireSameProcess()
		try await context.quit(peerSeesQuit: true)
		try context.requireStandardRegistration(attempt: 2)
		guard peer.evidence.registrations[1] == nil, peer.evidence.connections == 2 else {
			throw HarnessFailure.assertion("The rejected TLS connection registered or the retry did not reconnect")
		}
	}
}
