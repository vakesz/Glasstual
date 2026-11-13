import Foundation

/// A TLS server whose certificate does not validate: the trust sheet appears,
/// Continue lets registration proceed over TLS.
struct TLSAcceptScenario: Scenario {
	let name = "tlsAccept"
	let budget = Duration.seconds(90)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.tlsAccept)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.answerCertificate(continue: true)
		try await context.awaitRegistered()
		try context.requireSameProcess()
		try await context.quit(peerSeesQuit: true)
		try context.requireStandardRegistration(attempt: 1)
		guard peer.evidence.connections == 1 else {
			throw HarnessFailure.assertion("Expected one TLS connection, saw \(peer.evidence.connections)")
		}
	}
}
