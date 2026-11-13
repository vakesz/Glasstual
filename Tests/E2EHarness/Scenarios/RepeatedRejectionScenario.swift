import Foundation

/// Three rejected registrations in a row, then a successful one, all on one
/// application process, which then quits while connected.
struct RepeatedRejectionScenario: Scenario {
	let name = "repeatedRejection"
	let budget = Duration.seconds(120)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.repeatedRejection)
		try await context.server(AXID.RowState.disconnected)
		try await context.connectThroughRejections(3)
		try await context.connect()
		try await context.awaitRegistered()
		try context.requireSameProcess()
		try await context.quit(peerSeesQuit: true)
		for attempt in 1 ... 4 {
			try context.requireStandardRegistration(attempt: attempt)
		}
		guard peer.evidence.connections == 4 else {
			throw HarnessFailure.assertion("Expected four connections, saw \(peer.evidence.connections)")
		}
	}
}
