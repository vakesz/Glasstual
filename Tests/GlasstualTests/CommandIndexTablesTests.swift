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

/// The policy store used to be `@unchecked Sendable` behind a recursive lock.
/// It is plain main-actor state now, and what has to survive that is the
/// round trip through the defaults it persists to.
@MainActor
@Suite("STS policy store round trips")
struct STSPolicyStoreRoundTripTests {
	@Test("Policies for several hosts survive a reload from the same defaults")
	func policiesSurviveAReload() throws {
		let suiteName = "com.vakesz.glasstual.tests.sts.roundtrip.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suiteName))

		defer { defaults.removePersistentDomain(forName: suiteName) }

		let store = STSPolicyStore(userDefaults: defaults)
		let expiry = Date(timeIntervalSinceNow: 3600)

		store.setPolicy(STSPolicy(port: 6697, expiresAt: expiry, preload: false), forHost: "irc.example.net")
		store.setPolicy(STSPolicy(port: 7000, expiresAt: expiry, preload: true), forHost: "IRC.Example.ORG")

		let reloaded = STSPolicyStore(userDefaults: defaults)

		#expect(reloaded.enforcedEndpoint(forHost: "irc.example.net") == STSPolicyEndpoint(port: 6697))
		#expect(reloaded.enforcedEndpoint(forHost: "irc.example.org") == STSPolicyEndpoint(port: 7000))
		#expect(reloaded.enforcedEndpoint(forHost: "irc.example.com") == nil)
	}

	@Test("Hosts are matched without regard to case, in and out")
	func hostsAreMatchedCaseInsensitively() {
		let store = STSPolicyStore(userDefaults: nil)

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 3600), preload: false),
			forHost: "IRC.Example.NET"
		)

		#expect(store.enforcedEndpoint(forHost: "irc.example.net") == STSPolicyEndpoint(port: 6697))
		#expect(store.enforcedEndpoint(forHost: "IRC.EXAMPLE.NET") == STSPolicyEndpoint(port: 6697))

		store.removePolicy(forHost: "irc.EXAMPLE.net")

		#expect(store.enforcedEndpoint(forHost: "irc.example.net") == nil)
	}

	@Test("An expired policy is dropped on the way out, not served")
	func expiredPoliciesAreDropped() {
		let store = STSPolicyStore(userDefaults: nil)

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: -1), preload: false),
			forHost: "irc.example.net"
		)

		#expect(store.enforcedEndpoint(forHost: "irc.example.net") == nil)
	}
}
