import ApplicationServices
import Foundation

enum DCCScenario {
	static func run(kind: ScenarioKind, driver: AccessibilityDriver) async throws {
		let directory = try HarnessFiles.root.appendingPathComponent("dcc-download", isDirectory: true)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: false,
			attributes: [.posixPermissions: 0o700]
		)
		try await driver.typeAndSend("/msg fixture E2E_DCC_OFFER")
		let window = try await driver.window(titled: "File Transfers")
		var transferIdentifier: String?
		try await driver.wait("select offered DCC transfer row") { deadline in
			var identifiers: Set<String> = []
			_ = try driver.find(from: window, deadline: deadline) { node in
				let identifier = try driver.text(node, kAXIdentifierAttribute, deadline: deadline)
				let prefix = "file-transfer-filename-"
				guard identifier.hasPrefix(prefix),
				      try driver.text(node, kAXValueAttribute, deadline: deadline) == "e2e-transfer.bin"
				else { return false }
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
			guard let content = try driver
				.identified("file-transfer-row-\(identity)", from: window, deadline: deadline) else { return false }
			transferIdentifier = identity
			let row = try driver.nativeRow(containing: content, deadline: deadline)
			try driver.set(row, attribute: kAXSelectedAttribute, value: kCFBooleanTrue, deadline: deadline)
			return try driver.value(row, kAXSelectedAttribute, deadline: deadline) as? Bool == true
		}
		guard let transferIdentifier else { throw HarnessFailure.assertion("Fixture transfer identity missing") }
		try await driver.button("Start Transfer", from: window)
		try await driver.filePanel(directory, saving: false, in: window)
		let expected = kind == .dccCancel ? DCCFixturePeer.partialSize : DCCFixturePeer.size
		try await driver.wait("DCC row displays exact processed bytes") { deadline in
			guard let row = try driver.identified(
				"file-transfer-row-\(transferIdentifier)",
				from: window,
				deadline: deadline
			),
				let bytes = try driver.identified(
					"file-transfer-bytes-\(transferIdentifier)",
					from: row,
					deadline: deadline
				)
			else { return false }
			let count = try driver.value(bytes, kAXValueAttribute, deadline: deadline)
			return (count as? Int ?? Int(count as? String ?? "")) == expected
		}
		if kind == .dccCancel {
			try await driver.button("Cancel Transfer", from: window)
		}
		let status = kind == .dccCancel ? "Transfer from fixture is stopped. Control click to start." :
			"Transfer from fixture is complete. Control click to open in Finder."
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
		let file = directory.appendingPathComponent("e2e-transfer.bin")
		let handle = try FileHandle(forReadingFrom: file)
		defer { try? handle.close() }
		let bytes = try handle.read(upToCount: DCCFixturePeer.size + 1) ?? Data()
		guard bytes == DCCFixturePeer.bytes.prefix(expected)
		else { throw HarnessFailure.assertion("DCC destination bytes do not match fixture") }
		try HarnessFiles.write("\(expected) " + DCCFixturePeer.hash(bytes), to: "dcc-file-evidence")
		try await driver.closeWindow(window)
		// Return to the server console without introducing any app-private command path.
		try await driver.typeAndSend("/msg fixture E2E_DCC_DONE")
		try await driver
			.wait("DCC interaction finished on same IRC connection") { _ in
				try HarnessFiles.read("interaction-stage") == "2"
			}
	}
}
