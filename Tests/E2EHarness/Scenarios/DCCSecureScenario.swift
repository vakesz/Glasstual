import Foundation

/// A passive `DCC SSEND` from a peer never seen before: accepting it asks
/// about the peer's certificate, Trust and Remember lets the handshake finish,
/// and the file arrives byte for byte over TLS.
struct DCCSecureScenario: Scenario {
	let name = "dccSecure"
	let budget = Duration.seconds(150)

	func run(_ context: ScenarioContext) async throws {
		let peer = try await context.launchAgainstPeer(.dccSecure, passiveDCC: true)
		guard let dcc = peer.dcc else { throw HarnessFailure.setup("The DCC peer did not start") }
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.receiveTrustedSecureTransfer(from: dcc)
		try await context.finishDCC(peer)
	}
}

extension ScenarioContext {
	/// Asks the fixture for its first file, accepts it, trusts the certificate
	/// its sender presents and checks the download.
	func receiveTrustedSecureTransfer(from dcc: DCCFixturePeer) async throws {
		try await send("/msg fixture E2E_DCC_OFFER")
		try await driver.menu("fileTransfers")
		_ = try await startOfferedTransfer(knowing: [])
		try await answerAlert(AXID.dccCertificateFirstUse, with: AXID.alertDefault(AXID.dccCertificateFirstUse))
		try await requireDownload(of: dcc.filenames[0], from: dcc)
	}

	/// Selects the transfer that is listed beyond `known` and starts it.
	/// Returns every transfer listed.
	func startOfferedTransfer(knowing known: Set<String>) async throws -> Set<String> {
		let listed = try await until("the offered transfer is listed") { () throws -> Set<String>? in
			guard let window = try driver.window(AXID.fileTransfersWindow) else { return nil }
			let identities = try driver.all(withPrefix: AXID.fileTransferFilenamePrefix, in: window)
				.map { String($0.0.dropFirst(AXID.fileTransferFilenamePrefix.count)) }
			guard identities.count > known.count else { return nil }
			guard identities.count == known.count + 1, identities.allSatisfy({ UUID(uuidString: $0) != nil }),
			      known.isSubset(of: identities)
			else { throw HarnessFailure.assertion("Expected one more transfer row named by a transfer UUID") }
			return Set(identities)
		}
		guard let transfer = listed.subtracting(known).first else {
			throw HarnessFailure.assertion("The offered transfer is not listed")
		}
		try await driver.select(AXID.fileTransferRow(transfer)) { try self.driver.window(AXID.fileTransfersWindow) }
		try await driver.button(AXID.fileTransfersStart, inWindow: AXID.fileTransfersWindow)
		return listed
	}

	/// Waits for the whole file and for the sender to see every byte acknowledged.
	func requireDownload(of filename: String, from dcc: DCCFixturePeer) async throws {
		let file = sandbox.downloads.appendingPathComponent(filename)
		try await until("the download holds \(DCCFixturePeer.size) bytes") {
			(try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int == DCCFixturePeer.size
		}
		try await until("the sender saw the transfer end") { dcc.outcome != nil }
		let bytes = try Data(contentsOf: file)
		guard bytes == DCCFixturePeer.bytes, dcc.acknowledged == DCCFixturePeer.size else {
			throw HarnessFailure.assertion("The downloaded bytes or the acknowledgements did not match the fixture")
		}
		note("DCC: \(bytes.count) bytes, SHA-256 \(DCCFixturePeer.hash(bytes)), \(dcc.outcome ?? "")")
	}

	/// Closes the File Transfers window, tells the fixture the transfers are
	/// over and quits, all on the one IRC connection.
	func finishDCC(_ peer: LoopbackPeer) async throws {
		try await close(window: AXID.fileTransfersWindow)
		try await selectRow("server", ScenarioContext.network)
		try await send("/msg fixture E2E_DCC_DONE")
		try await until("the sender finished on the same IRC connection") { peer.evidence.interactionStage == 2 }
		try await quit(peerSeesQuit: true)
		guard peer.evidence.connections == 1 else {
			throw HarnessFailure.assertion("The transfers took more than one IRC connection")
		}
	}
}
