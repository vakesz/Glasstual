import AppKit
import ApplicationServices
import Foundation

enum SettingsSnapshotScenario {
	private static let confirmationLabel = "Request confirmation before quitting Glasstual"

	static func run(driver: AccessibilityDriver) async throws {
		try await driver.menu("Settings\u{2026}", in: "Glasstual")
		var settings: AXUIElement?
		try await driver.wait("General settings with confirmation toggle") { deadline in
			let windows = try driver.value(driver.root, kAXWindowsAttribute, deadline: deadline) as? [AXUIElement] ?? []
			for window in windows where try driver.named(
				confirmationLabel,
				role: kAXCheckBoxRole,
				from: window,
				deadline: deadline
			) != nil {
				settings = window
				return true
			}
			return false
		}
		guard let settings else { throw HarnessFailure.assertion("General Settings window missing") }
		try await toggle(driver, in: settings, from: false, to: true)
		let snapshot = try HarnessFiles.root.appendingPathComponent("synthetic-configuration.plist")
		try await driver.button("Export Configuration\u{2026}", from: settings)
		try await driver.wait("export options default excludes connect commands") { deadline in
			guard let toggle = try driver.named(
				"Include connect commands",
				role: kAXCheckBoxRole,
				from: settings,
				deadline: deadline
			) else { return false }
			guard try driver.value(toggle, kAXValueAttribute, deadline: deadline) as? Int == 0 else {
				throw HarnessFailure.assertion("Export unexpectedly includes connect commands by default")
			}
			return true
		}
		try await driver.button("Export", from: settings)
		try await driver.filePanel(snapshot, saving: true, in: settings)
		try await driver
			.wait("configuration export appears") { _ in FileManager.default.fileExists(atPath: snapshot.path) }
		try ConfigurationSnapshotFixture.validate(ConfigurationSnapshotFixture.read(snapshot))
		try await successAlert(driver, settings: settings, exported: true)
		try await toggle(driver, in: settings, from: true, to: false)
		try await driver.button("Import Configuration\u{2026}", from: settings)
		try await driver.filePanel(snapshot, saving: false, in: settings)
		try await preview(driver, settings: settings)
		try await driver.button("Merge", from: settings)
		try await successAlert(driver, settings: settings, exported: false)
		try await toggle(driver, in: settings, from: true, to: true)
		try await driver.button("Preview Recovery", from: settings)
		try await preview(driver, settings: settings)
		try await driver.button("Cancel", from: settings)
		try await toggle(driver, in: settings, from: true, to: false)
		try await driver.closeWindow(settings)
		try HarnessFiles.write("toggle exported; merge restored; recovery preview cancelled", to: "settings-roundtrip")
	}

	private static func toggle(
		_ driver: AccessibilityDriver,
		in window: AXUIElement,
		from old: Bool,
		to new: Bool
	) async throws {
		try await driver.wait("observe and change confirmation toggle") { deadline in
			guard let toggle = try driver.named(
				confirmationLabel,
				role: kAXCheckBoxRole,
				from: window,
				deadline: deadline
			) else { return false }
			guard try driver.value(toggle, kAXValueAttribute, deadline: deadline) as? Int == (old ? 1 : 0) else {
				throw HarnessFailure.assertion("Confirmation toggle differs from expected fixture state")
			}
			if old != new {
				try driver.press(toggle, deadline: deadline)
			}
			return true
		}
		try await driver.wait("confirmation toggle applied") { deadline in
			guard let toggle = try driver.named(
				confirmationLabel,
				role: kAXCheckBoxRole,
				from: window,
				deadline: deadline
			) else { return false }
			return try driver.value(toggle, kAXValueAttribute, deadline: deadline) as? Int == (new ? 1 : 0)
		}
	}

	private static func preview(_ driver: AccessibilityDriver, settings: AXUIElement) async throws {
		try await driver.wait("import preview identifies changed confirmation preference") { deadline in
			try driver.named(
				"Preview configuration import",
				role: kAXStaticTextRole,
				from: settings,
				deadline: deadline
			) != nil &&
				driver
				.named("ConfirmApplicationQuit", role: kAXStaticTextRole, from: settings, deadline: deadline) != nil
		}
	}

	private static func successAlert(_ driver: AccessibilityDriver, settings: AXUIElement,
	                                 exported: Bool) async throws
	{
		try await driver.wait("configuration transfer success alert") { deadline in
			try driver.find(from: settings, deadline: deadline) {
				let value = try driver.text($0, kAXValueAttribute, deadline: deadline)
				return exported ? value == "The configuration snapshot was exported successfully." :
					value.hasPrefix("Configuration imported. Settings changed:")
			} != nil
		}
		try await driver.button("OK", from: settings)
	}
}

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
		      let preferences = root["preferences"] as? [String: Any],
		      preferences["ConfirmApplicationQuit"] as? Bool == true,
		      root["unset"] is [String], let clients = root["clients"] as? [[String: Any]], clients.count == 1,
		      clients[0]["connectionName"] as? String == "E2E", clients[0]["nickname"] as? String == "e2euser",
		      clients[0]["loginCommands"] == nil,
		      let servers = clients[0]["serverList"] as? [[String: Any]], servers.count == 1,
		      servers[0]["serverAddress"] as? String == "127.0.0.1"
		else {
			throw HarnessFailure.assertion("Exported snapshot did not match the synthetic configuration")
		}
	}
}
