// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// A script may not take the name of a command that goes to the server.
struct ScriptCatalogForbiddenCommandsTests {
	private func bundledList() -> [String] {
		BundleResources.array(
			fromResources: StaticStoreResource.name,
			key: StaticStoreResource.forbiddenScriptCommandsKey,
			cacheValue: false
		)?.compactMap(\.string) ?? []
	}

	@Test("The bundled list is lowercase, unique and names the server commands a script could hijack")
	func bundledListShape() {
		let names = bundledList()

		#expect(names.isEmpty == false)
		#expect(names.allSatisfy { $0 == $0.lowercased() && $0.isEmpty == false })
		#expect(Set(names).count == names.count)
		#expect(Set(["kill", "oper", "pass", "ping", "pong", "squit", "restart"]).isSubset(of: names))
	}

	@Test("A script named after a forbidden command is not discovered, whatever its case or extension")
	func forbiddenScriptIsSkipped() throws {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let custom = root.appendingPathComponent("custom", isDirectory: true)
		let bundled = root.appendingPathComponent("bundled", isDirectory: true)
		defer { try? FileManager.default.removeItem(at: root) }
		for directory in [custom, bundled] {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}
		for name in ["KILL.SCPT", "Oper.scpt", "greet.scpt"] {
			try Data().write(to: custom.appendingPathComponent(name))
		}

		let catalog = ScriptCatalog.discover(customURL: custom, bundledURL: bundled, forbiddenCommands: Set(bundledList()))

		#expect(catalog.commandsByName["kill"] == nil)
		#expect(catalog.commandsByName["oper"] == nil)
		#expect(catalog.commandsByName["greet"] != nil)
	}
}
