import Foundation

/// A passive DCC SEND offered over IRC: accepted from the File Transfers
/// window, written byte for byte into the run's own Downloads folder, and
/// acknowledged in full to the sender.
struct DCCSuccessScenario: Scenario {
	let name = "dccSuccess"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		try await context.receiveDCC(cancelling: false)
	}
}

extension ScenarioContext {
	func receiveDCC(cancelling: Bool) async throws {
		let peer = try await launchAgainstPeer(cancelling ? .dccCancel : .dccSuccess, passiveDCC: true)
		guard let dcc = peer.dcc else { throw HarnessFailure.setup("The DCC peer did not start") }
		let file = sandbox.downloads.appendingPathComponent(dcc.filename)
		try await server(AXID.RowState.disconnected)
		try await connect()
		try await awaitRegistered()
		try await send("/msg fixture E2E_DCC_OFFER")
		// An unsolicited offer does not steal focus: open the list the way a reader does.
		try await driver.menu("fileTransfers")
		let transfer = try await until("the offered transfer is listed") { () throws -> String? in
			guard let window = try driver.window(AXID.fileTransfersWindow) else { return nil }
			let rows = try driver.all(withPrefix: AXID.fileTransferFilenamePrefix, in: window)
			guard rows.isEmpty == false else { return nil }
			guard rows.count == 1, let identity = rows.first?.0.dropFirst(AXID.fileTransferFilenamePrefix.count),
			      UUID(uuidString: String(identity)) != nil
			else { throw HarnessFailure.assertion("Expected one transfer row named by a transfer UUID") }
			return String(identity)
		}
		try await driver.select(AXID.fileTransferRow(transfer)) { try self.driver.window(AXID.fileTransfersWindow) }
		try await driver.button(AXID.fileTransfersStart, inWindow: AXID.fileTransfersWindow)
		let expected = cancelling ? DCCFixturePeer.partialSize : DCCFixturePeer.size
		try await until("the download holds \(expected) bytes") {
			(try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int == expected
		}
		if cancelling {
			try await driver.button(AXID.fileTransfersStop, inWindow: AXID.fileTransfersWindow)
		}
		try await until("the sender saw the transfer end") { dcc.outcome != nil }
		let handle = try FileHandle(forReadingFrom: file)
		let bytes = try handle.read(upToCount: DCCFixturePeer.size + 1) ?? Data()
		try handle.close()
		guard bytes == DCCFixturePeer.bytes.prefix(expected), dcc.acknowledged == expected else {
			throw HarnessFailure.assertion("The downloaded bytes or the acknowledgements did not match the fixture")
		}
		note("DCC: \(expected) bytes, SHA-256 \(DCCFixturePeer.hash(bytes)), \(dcc.outcome ?? "")")
		try await close(window: AXID.fileTransfersWindow)
		try await selectRow("server", ScenarioContext.network)
		try await send("/msg fixture E2E_DCC_DONE")
		try await until("the sender finished on the same IRC connection") { peer.evidence.interactionStage == 2 }
		try await quit(peerSeesQuit: true)
		guard peer.evidence.connections == 1 else {
			throw HarnessFailure.assertion("The transfer took more than one IRC connection")
		}
	}
}
