import Foundation

/** A channel that receives 10,000 names and 5,000 messages in fifteen seconds
 while the reader opens Settings, switches page and back to the channel and
 sends. Every Accessibility answer during the burst is within the
 responsiveness limit, and the member count is exact at the end. */
struct BurstResponsivenessScenario: Scenario {
	let name = "burstResponsiveness"
	let budget = Duration.seconds(180)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.burstResponsiveness)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.send("/join #e2e")
		try await context.transcript(contains: "E2E_CHANNEL_READY")
		try await context.send("/msg fixture E2E_BURST_START")
		for index in 1 ... 3 {
			guard peer.evidence.burstComplete == false else {
				throw HarnessFailure.assertion("The burst ended before switch \(index)")
			}
			try await context.openSettings()
			try await context.selectSettingsPage("general")
			try await context.until("General page shows during the burst") {
				try context.driver.element(AXID.settingsConfirmQuit, inWindow: AXID.settingsWindow) != nil
			}
			try await context.close(window: AXID.settingsWindow)
			try await context.selectRow("channel", "#e2e")
			try await context.send("/msg fixture E2E_BURST_SWITCH_\(index)")
			try await context.selectRow("channel", "#e2e")
			try await context.transcript(contains: "E2E_BURST_SWITCH_\(index)_ACK")
		}
		try await context.until("the peer finished the burst", timeout: .seconds(40)) { peer.evidence.burstComplete }
		try await context.transcript(contains: "E2E_BURST_END", timeout: .seconds(30))
		try await context.until("10,002 members listed", timeout: .seconds(30)) {
			guard let window = try context.mainWindow(),
			      let count = try context.driver.find(AXID.memberCount, in: window)
			else { return false }
			return try context.driver.value(count) == "10002"
		}
		try await context.quit(peerSeesQuit: true)
		guard peer.evidence.burstBatches == 100 else {
			throw HarnessFailure.assertion("The peer sent \(peer.evidence.burstBatches) of 100 batches")
		}
	}
}
