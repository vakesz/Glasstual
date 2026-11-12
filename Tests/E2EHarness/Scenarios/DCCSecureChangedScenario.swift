import Foundation

/// A peer whose certificate was trusted and remembered offers a second file
/// with a different certificate: the warning appears, and Cancel ends the
/// transfer before a byte of it is kept or acknowledged.
struct DCCSecureChangedScenario: Scenario {
	let name = "dccSecureChanged"
	let budget = Duration.seconds(180)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.dccSecureChanged, passiveDCC: true)
		guard let dcc = peer.dcc else { throw HarnessFailure.setup("The DCC peer did not start") }
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.receiveTrustedSecureTransfer(from: dcc)
		let known = try await context.until("the first transfer is listed") { () throws -> Set<String>? in
			guard let window = try context.driver.window(AXID.fileTransfersWindow) else { return nil }
			let rows = try context.driver.all(withPrefix: AXID.fileTransferFilenamePrefix, in: window)
			return rows.count == 1 ? Set(rows.map { String($0.0.dropFirst(AXID.fileTransferFilenamePrefix.count)) }) : nil
		}

		try await context.selectRow("server", ScenarioContext.network)
		try await context.send("/msg fixture E2E_DCC_OFFER_AGAIN")
		try await context.driver.menu("fileTransfers")
		_ = try await context.startOfferedTransfer(knowing: known)
		try await context.answerAlert(AXID.dccCertificateChanged, with: AXID.alertDefault(AXID.dccCertificateChanged))
		try await context.until("the sender saw the second transfer refused") { dcc.outcomes.count == 2 }
		guard dcc.outcomes.last == DCCFixturePeer.refused, dcc.acknowledged == nil else {
			throw HarnessFailure.assertion("Declining the changed certificate did not stop the transfer")
		}
		let second = context.sandbox.downloads.appendingPathComponent(dcc.filenames[1])
		let kept = (try? FileManager.default.attributesOfItem(atPath: second.path))?[.size] as? Int ?? 0
		guard kept == 0 else {
			throw HarnessFailure.assertion("\(kept) bytes of the refused transfer were written to Downloads")
		}
		try await context.finishDCC(peer)
	}
}
