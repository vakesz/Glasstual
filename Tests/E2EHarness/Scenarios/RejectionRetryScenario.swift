import Foundation

/// The server rejects the first registration; Connect again registers on the
/// same application process, and Disconnect closes the connection cleanly.
struct RejectionRetryScenario: Scenario {
	let name = "rejectionRetry"
	let budget = Duration.seconds(90)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.rejectionRetry)
		try await context.server(AXID.RowState.disconnected)
		try await context.connectThroughRejections(1)
		try await context.connect()
		try await context.awaitRegistered()
		try context.requireSameProcess()
		try await context.disconnect()
		try await context.quit(peerSeesQuit: false)
		try context.requireStandardRegistration(attempt: 1)
		try context.requireStandardRegistration(attempt: 2)
		guard peer.evidence.connections == 2, peer.evidence.disconnect == "QUIT and EOF" else {
			throw HarnessFailure.assertion("Expected two connections ending in QUIT and EOF")
		}
	}
}

extension ScenarioContext {
	/// Connects `count` times into a server that rejects registration, and
	/// waits each time for the rejection to show and the server to read
	/// disconnected.
	func connectThroughRejections(_ count: Int) async throws {
		for rejection in stride(from: 1, through: count, by: 1) {
			try await connect()
			try await transcript(contains: "E2E_REGISTRATION_REJECTED", occurrences: rejection)
			try await server(AXID.RowState.disconnected)
		}
	}
}
