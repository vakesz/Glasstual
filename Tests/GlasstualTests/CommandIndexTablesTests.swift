/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// The command tables replaced a lock-guarded, lazily populated store with one
/// immutable value. These pin the properties that made that swap safe: the
/// tables are complete when they are built, and the developer-mode split -- the
/// one thing the old cache had to invalidate -- is decided at build time.
@Suite("Command index tables")
struct CommandIndexTablesTests {
	@Test("Loading builds both tables")
	func loadingBuildsBothTables() {
		let tables = CommandIndexTables.loaded()

		#expect(tables.isEmpty == false)
		#expect(tables.local.isEmpty == false)
		#expect(tables.remote.isEmpty == false)
	}

	@Test("Loading twice produces the same tables")
	func loadingIsDeterministic() {
		let first = CommandIndexTables.loaded()
		let second = CommandIndexTables.loaded()

		#expect(first.local.count == second.local.count)
		#expect(first.remote.count == second.remote.count)
		#expect(first.local["join"]?.index == second.local["join"]?.index)
		#expect(first.commandNames(developerModeEnabled: true).sorted()
			== second.commandNames(developerModeEnabled: true).sorted())
	}

	@Test("A local entry carries the index, the syntax and the developer-mode flag")
	func localEntryRoundTripsItsFields() throws {
		let tables = CommandIndexTables.loaded()
		let join = try #require(tables.local["join"])

		#expect(join.index == 5032)
		#expect(join.isDeveloperModeOnly == false)

		let away = try #require(tables.local["away"])

		#expect(away.arguments == "[comment]")
	}

	@Test("A remote entry carries the index and the outgoing colon position")
	func remoteEntryRoundTripsItsFields() throws {
		let tables = CommandIndexTables.loaded()
		let privmsg = try #require(tables.remote["privmsg"])

		#expect(privmsg.index == 1035)
		#expect(privmsg.outgoingColonIndex == 1)
	}

	@Test("Developer-mode commands are in one list and not the other")
	func developerModeSplitIsSettledAtBuildTime() {
		let tables = CommandIndexTables.loaded()

		let all = Set(tables.commandNames(developerModeEnabled: true))
		let visible = Set(tables.commandNames(developerModeEnabled: false))

		#expect(visible.isSubset(of: all))
		#expect(all.count == tables.local.count)

		let developerOnly = Set(
			tables.local
				.filter(\.value.isDeveloperModeOnly)
				.keys
				.map { $0.uppercased() }
		)

		#expect(all.subtracting(visible) == developerOnly)
		#expect(visible.isDisjoint(with: developerOnly))
	}

	@Test("A name the index has never heard of is absent from both tables")
	func unknownCommandIsAbsent() {
		let tables = CommandIndexTables.loaded()

		#expect(tables.local["not-a-command"] == nil)
		#expect(tables.remote["not-a-command"] == nil)
	}
}
