import ApplicationServices
import Foundation

enum DCCScenario {
	static func run(kind: ScenarioKind, driver: AccessibilityDriver) async throws {
		let filename = try HarnessFiles.read("dcc-filename")
		guard let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
		else { throw HarnessFailure.setup("Downloads folder is unavailable") }
		let file = directory.appendingPathComponent(filename)
		guard FileManager.default.fileExists(atPath: file.path) == false
		else { throw HarnessFailure.setup("Unique DCC fixture filename already exists") }
		defer { try? FileManager.default.removeItem(at: file) }
		try await driver.typeAndSend("/msg fixture E2E_DCC_OFFER")
		/* An unsolicited offer deliberately does not steal focus. Open the list
		 through the same Window command a reader uses, then observe the row when
		 the offer arrives. */
		try await driver.menu("File Transfers", in: "Window")
		let window = try await driver.window(titled: "File Transfers")
		var transferIdentifier: String?
		try await driver.wait("select offered DCC transfer row") { deadline in
			var identifiers: Set<String> = []
			_ = try driver.find(from: window, deadline: deadline) { node in
				let identifier = try driver.text(node, kAXIdentifierAttribute, deadline: deadline)
				let prefix = "file-transfer-filename-"
				guard identifier.hasPrefix(prefix) else { return false }
				let identity = String(identifier.dropFirst(prefix.count))
				guard UUID(uuidString: identity) != nil
				else { throw HarnessFailure.assertion("Transfer AX identity is not a controller UUID") }
				identifiers.insert(identity)
				return false
			}
			guard !identifiers.isEmpty else { return false }
			guard identifiers.count == 1,
			      let identity = identifiers.first
			else { throw HarnessFailure.assertion("Ambiguous fixture transfer rows") }
			transferIdentifier = identity
			return true
		}
		guard let transferIdentifier else { throw HarnessFailure.assertion("Fixture transfer identity missing") }
		try await driver.clickRow(filename, from: window)
		try await driver.button("Accept", from: window)
		let expected = kind == .dccCancel ? DCCFixturePeer.partialSize : DCCFixturePeer.size
		try await driver.wait("DCC writes exact bytes to Downloads") { _ in
			let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
			return attributes?[.size] as? Int == expected
		}
		if kind == .dccCancel {
			try await driver.button("Cancel Transfer", from: window)
		}
		let status = kind == .dccCancel
			? "Transfer from fixture has not started. Choose Accept to begin."
			: "Received from fixture."
		try await driver.wait("DCC terminal row status and peer closure") { deadline in
			guard try HarnessFiles.exists("dcc-peer-complete"),
			      let row = try driver.identified(
			      	"file-transfer-row-\(transferIdentifier)",
			      	from: window,
			      	deadline: deadline
			      ),
			      let label = try driver.identified(
			      	"file-transfer-status-\(transferIdentifier)",
			      	from: row,
			      	deadline: deadline
			      ) else { return false }
			return try driver.text(label, kAXValueAttribute, deadline: deadline) == status
		}
		let handle = try FileHandle(forReadingFrom: file)
		defer { try? handle.close() }
		let bytes = try handle.read(upToCount: DCCFixturePeer.size + 1) ?? Data()
		guard bytes == DCCFixturePeer.bytes.prefix(expected)
		else { throw HarnessFailure.assertion("DCC destination bytes do not match fixture") }
		try HarnessFiles.write("\(expected) " + DCCFixturePeer.hash(bytes), to: "dcc-file-evidence")
		try await driver.closeWindow(window)
		try await driver.typeAndSend("/msg fixture E2E_DCC_DONE")
		try await driver
			.wait("DCC interaction finished on same IRC connection") { _ in
				try HarnessFiles.read("interaction-stage") == "2"
			}
	}
}
