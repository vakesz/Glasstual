import Foundation

/// `/xdcc send` asks a bot for a pack: the request waits in File Transfers
/// until the bot's offer arrives, the offer takes its place, and the pack
/// downloads byte for byte.
struct XDCCRequestScenario: Scenario {
	let name = "xdccRequest"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.xdccRequest, passiveDCC: true)
		guard let dcc = peer.dcc else { throw HarnessFailure.setup("The DCC peer did not start") }
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.send("/xdcc send fixture 1")
		try await context.driver.menu("fileTransfers")
		try await context.until("the request waits for its bot") {
			try peer.evidence.offerHeld && context.pendingXDCCRequests() == 1
		}
		guard try context.driver.window(AXID.fileTransfersWindow)
			.map({ try context.driver.all(withPrefix: AXID.fileTransferFilenamePrefix, in: $0).isEmpty }) == true
		else { throw HarnessFailure.assertion("A transfer was listed before the bot offered the pack") }

		try peer.releaseHeldOffer()
		_ = try await context.startOfferedTransfer(knowing: [])
		try await context.until("the offer took the request's place") { try context.pendingXDCCRequests() == 0 }
		try await context.requireDownload(of: dcc.filenames[0], from: dcc)
		try await context.finishDCC(peer)
	}
}

private extension ScenarioContext {
	/// How many requests the File Transfers window lists as waiting, or `nil`
	/// while the window is not up.
	func pendingXDCCRequests() throws -> Int? {
		try driver.window(AXID.fileTransfersWindow)
			.map { try driver.all(withPrefix: AXID.xdccRequestRowPrefix, in: $0).count }
	}
}
