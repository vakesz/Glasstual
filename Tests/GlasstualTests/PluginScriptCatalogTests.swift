/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Script command catalog")
struct PluginScriptCatalogTests {
	@Test("Discovery is deterministic, custom-first, regular-file-only and case-insensitive for AppleScript")
	func discoveryClassifiesAndResolvesCollisions() throws {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let custom = root.appendingPathComponent("custom", isDirectory: true)
		let bundled = root.appendingPathComponent("bundled", isDirectory: true)
		try manager.createDirectory(at: custom, withIntermediateDirectories: true)
		try manager.createDirectory(at: bundled, withIntermediateDirectories: true)
		defer { try? manager.removeItem(at: root) }
		for name in ["HELLO.SCPT", "collision.sh", "collision.scpt", "join.scpt", "ignored.txt", ".hidden.scpt"] {
			try Data().write(to: custom.appendingPathComponent(name))
		}
		try manager.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: custom.appendingPathComponent("collision.sh").path
		)
		try manager.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: custom.appendingPathComponent("HELLO.SCPT").path
		)
		try Data().write(to: bundled.appendingPathComponent("hello.scpt"))
		try Data().write(to: bundled.appendingPathComponent("bundled.scpt"))
		try manager.createDirectory(
			at: custom.appendingPathComponent("directory.scpt"),
			withIntermediateDirectories: false
		)
		try manager.createSymbolicLink(
			at: custom.appendingPathComponent("link.scpt"),
			withDestinationURL: custom.appendingPathComponent("HELLO.SCPT")
		)

		let catalog = PluginScriptCatalog.discover(customURL: custom, bundledURL: bundled, forbiddenCommands: ["join"])
		#expect(Set(catalog.commandsByName.keys) == ["hello", "collision", "bundled"])
		#expect(catalog.commandsByName["hello"]?.url.lastPathComponent == "HELLO.SCPT")
		#expect(catalog.commandsByName["hello"]?.kind == .appleScript)
		#expect(catalog.commandsByName["hello"]?.origin == .custom)
		#expect(catalog.commandsByName["bundled"]?.origin == .bundled)
		#expect(catalog.commandsByName["collision"]?.url.lastPathComponent == "collision.scpt")
		#expect(PluginScript(url: custom.appendingPathComponent("collision.sh"), origin: .custom)?
			.kind == .unixExecutable)
		#expect(PluginScriptCatalog.discover(
			customURL: custom, bundledURL: bundled, forbiddenCommands: ["join"]
		).commandsByName == catalog.commandsByName)
	}
}
