import Foundation

/// Messages exchanged in one launch are in the channel's transcript after a
/// relaunch, read back from the stored history without connecting.
struct HistoryRelaunchScenario: Scenario {
	let name = "historyRelaunch"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.historyRelaunch, keepsState: true)
		try await context.exchangeChannelMessages(checkingColumns: false)
		try await context.quit(peerSeesQuit: true)
		try context.requireChannelExchange()

		let first = try context.current
		try await context.launch(seed: nil)
		guard try context.current.pid != first.pid else {
			throw HarnessFailure.assertion("The relaunch did not start a new process")
		}
		try await context.selectRow("channel", "#e2e")
		try await context.until("#e2e is not joined after the relaunch") {
			try context.rowState("channel", "#e2e") == AXID.RowState.notJoined
		}
		for marker in ["E2E_TYPED_MESSAGE", "E2E_SERVER_REPLY", "E2E_REPLY_ACK"] {
			try await context.transcript(contains: marker)
		}
		try await context.quit(peerSeesQuit: false)
	}
}
