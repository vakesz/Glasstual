// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** Keychain items are filed under the identifiers of the models that own them,
 so a file that sends a known session somewhere new would carry that
 session's passwords there. The plan turns such a session into a different
 network, and says so. */
@MainActor
@Suite("Settings transfer plan")
struct SettingsTransferPlanTests {
	private static let home = SettingsRiskyChange.Endpoint(host: "irc.example.test", port: 6697, isEncrypted: true)

	private func existingSession() -> ServerConfig {
		var config = ServerConfig(connectionName: "Example")
		config.nickname = "TestNick"
		config.username = "test"
		config.realName = "Test User"
		config.awayNickname = ""
		config.serverList = [ServerEndpoint(serverAddress: "irc.example.test", serverPort: 6697, prefersSecuredConnection: true)]
		config.conversationList = [ConversationConfig(name: "#test")]
		return config
	}

	private func makePlan(
		importing imported: ServerConfig,
		over existing: [ServerConfig],
		mode: SettingsTransferMode = .merge,
		source: SettingsArchive.Source = .portable,
		omittingCommands: Bool = false
	) throws -> SettingsTransferPlan {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		var archive = SettingsArchive(values: [:], unset: [], sessions: [imported])
		archive.source = source
		if omittingCommands {
			archive.omittedConnectCommands = [imported.uniqueIdentifier]
		}
		return try SettingsTransferPlan(
			archive: archive,
			current: SettingsArchive.snapshot(from: fixture.stores, sessions: existing),
			mode: mode
		)
	}

	private func moved(_ existing: ServerConfig, to host: String) -> ServerConfig {
		var imported = existing
		imported.serverList[0].serverAddress = host
		return imported
	}

	@Test("A session that keeps its endpoint is updated in place")
	func sameEndpointKeepsIdentity() throws {
		let existing = existingSession()
		var imported = existing
		imported.nickname = "Renamed"

		let plan = try makePlan(importing: imported, over: [existing])

		#expect(plan.result.sessions?.map(\.uniqueIdentifier) == [existing.uniqueIdentifier])
		#expect(plan.updatedSessions == ["Example"])
		#expect(plan.addedSessions.isEmpty)
		#expect(plan.riskyChanges.contains {
			if case .serverEndpoint = $0 {
				true
			} else {
				false
			}
		} == false)
	}

	@Test("A new host becomes a separate network with identities nothing is stored under")
	func movedHostIsANewNetwork() throws {
		var existing = existingSession()
		existing.loginCommands = ["/msg NickServ IDENTIFY secret"]
		existing.identityClientSideCertificate = Data([1, 2, 3])
		var imported = moved(existing, to: "irc.other.test")
		imported.loginCommands = []
		imported.identityClientSideCertificate = nil

		let plan = try makePlan(importing: imported, over: [existing], omittingCommands: true)

		let sessions = try #require(plan.result.sessions)
		#expect(sessions.count == 2)
		#expect(sessions[0] == existing)
		let created = sessions[1]
		#expect(created.uniqueIdentifier != existing.uniqueIdentifier)
		#expect(created.serverList[0].uniqueIdentifier != existing.serverList[0].uniqueIdentifier)
		#expect(created.conversationList[0].uniqueIdentifier != existing.conversationList[0].uniqueIdentifier)
		#expect(created.serverList[0].serverAddress == "irc.other.test")
		#expect(created.pendingNicknamePassword == .unchanged)
		#expect(created.serverList[0].pendingServerPassword == .unchanged)
		#expect(created.loginCommands.isEmpty)
		#expect(created.identityClientSideCertificate == nil)
		#expect(plan.addedSessions == ["Example"])
		#expect(plan.updatedSessions.isEmpty)
		#expect(plan.removedSessions.isEmpty)
		#expect(plan.riskyChanges.contains(.serverEndpoint(
			server: "Example",
			from: Self.home,
			to: .init(host: "irc.other.test", port: 6697, isEncrypted: true),
			outcome: .newServerExistingKept
		)))
		#expect(plan.riskyChanges.contains {
			if case .newDestination = $0 {
				true
			} else {
				false
			}
		} == false)
	}

	@Test("Restore replaces the session, whose history is not carried over")
	func restoreReplacesTheMovedSession() throws {
		let existing = existingSession()

		let plan = try makePlan(importing: moved(existing, to: "irc.other.test"), over: [existing], mode: .restore)

		let sessions = try #require(plan.result.sessions)
		#expect(sessions.count == 1)
		#expect(sessions[0].uniqueIdentifier != existing.uniqueIdentifier)
		#expect(plan.removedSessions == ["Example"])
		#expect(plan.addedSessions == ["Example"])
		#expect(plan.riskyChanges.contains { change in
			if case .serverEndpoint(_, _, _, .newServerExistingRemoved) = change {
				true
			} else {
				false
			}
		})
	}

	@Test("A new port or a new proxy is a new destination too", arguments: ["port", "proxy"])
	func portAndProxyMoveCredentials(_ change: String) throws {
		var existing = existingSession()
		existing.proxyType = .socks5
		existing.proxyAddress = "proxy.example.test"
		var imported = existing
		if change == "port" {
			imported.serverList[0].serverPort = 6667
		} else {
			imported.proxyAddress = "proxy.other.test"
		}

		let plan = try makePlan(importing: imported, over: [existing])

		#expect(plan.result.sessions?.count == 2)
		#expect(plan.addedSessions == ["Example"])
	}

	@Test("Dropping a server sends credentials nowhere new")
	func narrowedServerListKeepsIdentity() throws {
		var existing = existingSession()
		existing.serverList.append(ServerEndpoint(serverAddress: "backup.example.test", serverPort: 6697))
		var imported = existing
		imported.serverList.removeLast()

		let plan = try makePlan(importing: imported, over: [existing])

		#expect(plan.result.sessions?.map(\.uniqueIdentifier) == [existing.uniqueIdentifier])
	}

	@Test("Turning encryption off is shown but keeps the session")
	func encryptionChangeIsShown() throws {
		let existing = existingSession()
		var imported = existing
		imported.serverList[0].prefersSecuredConnection = false

		let plan = try makePlan(importing: imported, over: [existing])

		#expect(plan.result.sessions?.map(\.uniqueIdentifier) == [existing.uniqueIdentifier])
		#expect(plan.riskyChanges.contains(.serverEndpoint(
			server: "Example",
			from: Self.home,
			to: .init(host: "irc.example.test", port: 6697, isEncrypted: false),
			outcome: .sameServer
		)))
	}

	@Test("Turning certificate checking off is shown, and leaving it on is not")
	func certificateValidationIsShown() throws {
		let existing = existingSession()
		var disabled = existing
		disabled.validateServerCertificateChain = false

		let shown = try makePlan(importing: disabled, over: [existing])
		let quiet = try makePlan(importing: existing, over: [existing])

		#expect(shown.riskyChanges.contains(.certificateValidationDisabled(server: "Example")))
		#expect(shown.result.sessions?.map(\.uniqueIdentifier) == [existing.uniqueIdentifier])
		#expect(quiet.riskyChanges.contains(.certificateValidationDisabled(server: "Example")) == false)
	}

	@Test("The same file makes the same network, so a second import updates it")
	func derivedIdentitiesAreStable() throws {
		let existing = existingSession()
		let imported = moved(existing, to: "irc.other.test")
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let first = try makePlan(importing: imported, over: [existing])
		let again = try makePlan(importing: imported, over: [existing])
		#expect(first.result.sessions?[1].uniqueIdentifier == again.result.sessions?[1].uniqueIdentifier)

		let second = try SettingsTransferPlan(
			archive: SettingsArchive(values: [:], unset: [], sessions: [imported]),
			current: SettingsArchive.snapshot(from: fixture.stores, sessions: first.result.sessions ?? []),
			mode: .merge
		)

		#expect(second.result.sessions?.count == 2)
		#expect(second.addedSessions.isEmpty)
		#expect(second.riskyChanges.contains {
			if case .serverEndpoint = $0 {
				true
			} else {
				false
			}
		} == false)
	}

	@Test("The app's own recovery backup keeps its identities")
	func localRecoveryIsLeftAlone() throws {
		let existing = existingSession()

		let plan = try makePlan(importing: moved(existing, to: "irc.other.test"), over: [existing], source: .localRecovery)

		#expect(plan.result.sessions?.map(\.uniqueIdentifier) == [existing.uniqueIdentifier])
		#expect(plan.riskyChanges.isEmpty)
	}

	private func newDestinations(in plan: SettingsTransferPlan) -> [SettingsRiskyChange] {
		plan.riskyChanges.filter {
			if case .newDestination = $0 {
				true
			} else {
				false
			}
		}
	}

	private func hasEndpointLine(_ plan: SettingsTransferPlan) -> Bool {
		plan.riskyChanges.contains {
			if case .serverEndpoint = $0 {
				true
			} else {
				false
			}
		}
	}

	@Test("A second server the file adds is named, and the unchanged first one is not")
	func addedServerIsNamed() throws {
		let existing = existingSession()
		var imported = existing
		imported.serverList.append(ServerEndpoint(serverAddress: "Backup.example.test", serverPort: 6667))

		let plan = try makePlan(importing: imported, over: [existing])

		#expect(plan.result.sessions?.count == 2)
		#expect(hasEndpointLine(plan) == false)
		#expect(newDestinations(in: plan) == [.newDestination(
			server: "Example",
			destination: .server(.init(host: "Backup.example.test", port: 6667, isEncrypted: false)),
			mode: .merge
		)])
	}

	@Test("A moved first server is named once, and only the other additions get their own line")
	func movedFirstServerIsNotRepeated() throws {
		let existing = existingSession()
		var imported = moved(existing, to: "irc.other.test")
		imported.serverList.append(ServerEndpoint(serverAddress: "backup.example.test", serverPort: 6697))

		let plan = try makePlan(importing: imported, over: [existing])

		#expect(plan.riskyChanges.filter {
			if case .serverEndpoint = $0 {
				true
			} else {
				false
			}
		}.count == 1)
		#expect(newDestinations(in: plan) == [.newDestination(
			server: "Example",
			destination: .server(.init(host: "backup.example.test", port: 6697, isEncrypted: false)),
			mode: .merge
		)])
	}

	@Test("A proxy the file adds is named")
	func newProxyIsNamed() throws {
		var existing = existingSession()
		existing.proxyType = .socks5
		existing.proxyAddress = "proxy.example.test"
		var imported = existing
		imported.proxyAddress = "proxy.other.test"

		let plan = try makePlan(importing: imported, over: [existing])

		#expect(newDestinations(in: plan) == [.newDestination(
			server: "Example", destination: .proxy(host: "proxy.other.test", port: imported.proxyPort), mode: .merge
		)])
	}

	@Test("Restore says the same thing in its own words")
	func restoreCarriesItsMode() throws {
		let existing = existingSession()
		var imported = existing
		imported.serverList.append(ServerEndpoint(serverAddress: "backup.example.test", serverPort: 6697))

		let plan = try makePlan(importing: imported, over: [existing], mode: .restore)

		#expect(newDestinations(in: plan).count == 1)
		#expect(newDestinations(in: plan).allSatisfy {
			if case .newDestination(_, _, .restore) = $0 {
				true
			} else {
				false
			}
		})
	}

	@Test("An import that already made the network names nothing again")
	func importedNetworkIsNotShownTwice() throws {
		let existing = existingSession()
		var imported = existing
		imported.serverList.append(ServerEndpoint(serverAddress: "backup.example.test", serverPort: 6697))
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let first = try makePlan(importing: imported, over: [existing])

		let second = try SettingsTransferPlan(
			archive: SettingsArchive(values: [:], unset: [], sessions: [imported]),
			current: SettingsArchive.snapshot(from: fixture.stores, sessions: first.result.sessions ?? []),
			mode: .merge
		)

		#expect(newDestinations(in: first).count == 1)
		#expect(newDestinations(in: second).isEmpty)
	}

	@Test("Dropping a server or restoring a backup names no destination")
	func nothingNewNamesNothing() throws {
		var existing = existingSession()
		existing.serverList.append(ServerEndpoint(serverAddress: "backup.example.test", serverPort: 6697))
		var narrowed = existing
		narrowed.serverList.removeLast()
		var widened = existing
		widened.serverList.append(ServerEndpoint(serverAddress: "third.example.test", serverPort: 6697))

		#expect(try newDestinations(in: makePlan(importing: narrowed, over: [existing])).isEmpty)
		#expect(try newDestinations(in: makePlan(importing: widened, over: [existing], source: .localRecovery)).isEmpty)
	}

	private func preview(merge: SettingsTransferPlan?, restore: SettingsTransferPlan?) -> SettingsTransferPreview {
		let empty = SettingsArchive(values: [:], unset: [], sessions: [])
		var plans: [SettingsTransferMode: SettingsTransferPlan] = [:]
		plans[.merge] = merge
		plans[.restore] = restore
		return SettingsTransferPreview(filename: "settings.plist", archive: empty, current: empty, plans: plans)
	}

	@Test("Return applies a Merge with nothing to review")
	func returnMergesQuietFile() throws {
		let existing = existingSession()
		var imported = existing
		imported.nickname = "Renamed"
		let plan = try makePlan(importing: imported, over: [existing])

		#expect(preview(merge: plan, restore: nil).commitIsDefaultAction)
	}

	@Test("Return never applies a Restore, a file with changes to review, or a file that cannot be applied")
	func returnLeavesDecisionsToThePerson() throws {
		let existing = existingSession()
		var imported = existing
		imported.nickname = "Renamed"
		let quiet = try makePlan(importing: imported, over: [existing])
		let risky = try makePlan(importing: moved(existing, to: "irc.other.test"), over: [existing])
		let restore = try makePlan(importing: imported, over: [existing], mode: .restore)

		var restoring = preview(merge: quiet, restore: restore)
		restoring.mode = .restore
		#expect(restoring.commitIsDefaultAction == false)
		#expect(risky.riskyChanges.isEmpty == false)
		#expect(preview(merge: risky, restore: nil).commitIsDefaultAction == false)
		#expect(preview(merge: nil, restore: nil).commitIsDefaultAction == false)
	}
}
