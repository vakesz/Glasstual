// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Script catalog store")
struct ScriptCatalogStoreTests {
	private func catalog(named names: [String]) throws -> (ScriptCatalog, URL) {
		let manager = FileManager.default
		let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let custom = root.appendingPathComponent("custom", isDirectory: true)
		let bundled = root.appendingPathComponent("bundled", isDirectory: true)
		try manager.createDirectory(at: custom, withIntermediateDirectories: true)
		try manager.createDirectory(at: bundled, withIntermediateDirectories: true)
		for name in names {
			try Data().write(to: custom.appendingPathComponent("\(name).scpt"))
		}
		return (ScriptCatalog.discover(customURL: custom, bundledURL: bundled, forbiddenCommands: []), root)
	}

	@Test("Command names are sorted and follow the published catalog")
	func commandNamesFollowThePublishedCatalog() throws {
		let (first, firstRoot) = try catalog(named: ["zeta", "alpha", "mid"])
		let (second, secondRoot) = try catalog(named: ["beta"])
		defer {
			try? FileManager.default.removeItem(at: firstRoot)
			try? FileManager.default.removeItem(at: secondRoot)
		}

		let store = ScriptCatalogStore(catalog: first)
		#expect(store.commandNames == ["alpha", "mid", "zeta"])

		store.publish(second, generation: 0)
		#expect(store.commandNames == ["beta"])
	}

	@Test("A catalog from an overtaken scan leaves the names alone")
	func overtakenScanIsDropped() throws {
		let (first, firstRoot) = try catalog(named: ["alpha"])
		let (stale, staleRoot) = try catalog(named: ["stale"])
		defer {
			try? FileManager.default.removeItem(at: firstRoot)
			try? FileManager.default.removeItem(at: staleRoot)
		}

		let store = ScriptCatalogStore(catalog: first)
		store.publish(stale, generation: 7)

		#expect(store.commandNames == ["alpha"])
	}
}
