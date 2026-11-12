import ApplicationServices
import Foundation

/** Export the configuration with a changed setting, change it back, import
 the export with Merge, and preview a recovery backup without applying it.

 The save and open panels are the system's. In an end-to-end run they open
 in the run's own `Transfers` folder, so the harness presses Export as it
 stands and opens the one file the folder holds, by Accessibility like every
 other step. */
struct SettingsSnapshotScenario: Scenario {
	let name = "settingsSnapshot"
	let budget = Duration.seconds(180)

	func run(_ context: ScenarioContext) async throws {
		try await context.launchAgainstPeer(.registration)
		try await context.server(AXID.RowState.disconnected)
		try await context.connect()
		try await context.awaitRegistered()
		try await context.disconnect()

		try await context.openSettings()
		try await context.selectSettingsPage("general")
		try await context.confirmQuit(is: false, becomes: true)

		try await context.driver.button(AXID.settingsExport, inWindow: AXID.settingsWindow)
		try await context.until("export options default to leaving connect commands out") {
			guard let toggle = try context.driver.anywhere(AXID.settingsExportIncludeCommands),
			      let value = try context.driver.number(toggle)
			else { return false }
			guard value == 0 else {
				throw HarnessFailure.assertion("Export includes connect commands by default")
			}
			return true
		}
		try await context.driver.button(AXID.settingsExportSave)
		try await context.confirmPanel(AXID.savePanel)
		let folder = context.sandbox.transfers
		let snapshot = try await context.until("the export is written") {
			try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
				.first { $0.pathExtension == "plist" }
		}
		try await context.until("the export is complete") {
			(try? ConfigurationSnapshotFixture.validate(ConfigurationSnapshotFixture.read(snapshot))) != nil
		}
		try await context.acknowledgeTransferResult()

		try await context.confirmQuit(is: true, becomes: false)
		try await context.driver.button(AXID.settingsImport, inWindow: AXID.settingsWindow)
		try await context.open(snapshot.lastPathComponent)
		try await context.awaitPreviewListingConfirmQuit()
		try await context.driver.button(AXID.settingsTransferCommit)
		try await context.acknowledgeTransferResult()
		try await context.confirmQuit(is: true, becomes: true)

		try await context.driver.button(AXID.settingsRecoveryPreview, inWindow: AXID.settingsWindow)
		try await context.awaitPreviewListingConfirmQuit()
		try await context.driver.button(AXID.settingsTransferCancel)
		try await context.until("recovery preview closes") { try context.driver.anywhere(AXID.settingsTransferPreview) == nil }
		try await context.confirmQuit(is: true, becomes: false)
		try await context.close(window: AXID.settingsWindow)
		try await context.quit(peerSeesQuit: false)
	}
}

private extension ScenarioContext {
	/// Requires the confirm-quit switch to read `old`, then sets it to `new`.
	func confirmQuit(is old: Bool, becomes new: Bool) async throws {
		try await until("confirm-quit switch reads \(old)") {
			guard let toggle = try driver.element(AXID.settingsConfirmQuit, inWindow: AXID.settingsWindow),
			      let value = try driver.number(toggle)
			else { return false }
			guard value == (old ? 1 : 0) else {
				throw HarnessFailure.assertion("The confirm-quit switch read \(value), expected \(old ? 1 : 0)")
			}
			return true
		}
		try await driver.toggle(AXID.settingsConfirmQuit, inWindow: AXID.settingsWindow, to: new)
	}

	/// The system panel `panel` attached to the Settings window.
	private func panel(_ panel: String) throws -> AXUIElement? {
		try driver.window(AXID.settingsWindow).flatMap { try driver.find(panel, in: $0) }
	}

	/// Presses the default button of `panel` and waits for the panel to close.
	func confirmPanel(_ name: String) async throws {
		try await until("\(name)") { try panel(name) != nil }
		try await driver.press("\(name) default button") {
			try panel(name).flatMap { try driver.find(AXID.panelDefaultButton, in: $0) }
		}
		try await until("\(name) closes") { try panel(name) == nil }
	}

	/** Opens `file` from the open panel: the Open action on its entry in the
	 browser's last column, which is the run's folder. Only that column is
	 read, so the walk never lists the person's folders. */
	func open(_ file: String) async throws {
		try await until("\(file) in the open panel") { try panel(AXID.openPanel) != nil }
		var attempted = false
		try await until("open \(file)") {
			// Opening closes the panel, which can take the action's reply with it.
			guard let panel = try panel(AXID.openPanel) else { return attempted }
			guard let browser = try driver.find(AXID.panelBrowser, in: panel),
			      let column = try driver.all(role: kAXListRole, in: browser).last
			else { return false }
			for entry in try driver.children(column) {
				for field in try driver.children(entry) where try driver.value(field) == file {
					attempted = true
					try driver.perform("AXOpen", on: field)
					return true
				}
			}
			return false
		}
		try await until("open panel closes") { try panel(AXID.openPanel) == nil }
	}

	/// The import or recovery preview is up and lists the confirm-quit setting.
	func awaitPreviewListingConfirmQuit() async throws {
		try await until("transfer preview lists the confirm-quit setting") {
			guard let preview = try driver.anywhere(AXID.settingsTransferPreview) else { return false }
			return try driver.find(AXID.settingsTransferChange(SettingsKey.confirmQuit), in: preview) != nil
		}
	}

	/// Confirms the alert that reports a finished export or import.
	func acknowledgeTransferResult() async throws {
		try await until("transfer result alert") { try driver.anywhere(AXID.settingsTransferResultConfirm) != nil }
		try await driver.button(AXID.settingsTransferResultConfirm)
		try await until("transfer result alert closes") { try driver.anywhere(AXID.settingsTransferResultConfirm) == nil }
	}
}

/// What the export has to contain: the synthetic configuration and nothing else.
enum ConfigurationSnapshotFixture {
	static func read(_ url: URL) throws -> Data {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		return try handle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
	}

	static func validate(_ data: Data) throws {
		var format = PropertyListSerialization.PropertyListFormat.xml
		guard data.count <= 16 * 1024 * 1024,
		      let root = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any],
		      format == .xml,
		      root["format"] as? String == "GlasstualConfiguration", root["version"] as? Int == 1,
		      let settings = root["preferences"] as? [String: Any],
		      settings[SettingsKey.confirmQuit] as? Bool == true,
		      root["unset"] is [String], let clients = root["clients"] as? [[String: Any]], clients.count == 1,
		      clients[0]["connectionName"] as? String == "E2E", clients[0]["nickname"] as? String == "e2euser",
		      clients[0]["loginCommands"] == nil,
		      let servers = clients[0]["serverList"] as? [[String: Any]], servers.count == 1,
		      servers[0]["serverAddress"] as? String == "127.0.0.1"
		else {
			throw HarnessFailure.assertion("The exported snapshot did not match the synthetic configuration")
		}
	}
}
