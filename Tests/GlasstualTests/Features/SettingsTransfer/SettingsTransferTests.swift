// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Configuration transfer and recovery")
struct SettingsTransferTests {
	private typealias Fixture = SettingsTransferFixture

	@Test("Cancelled transfer preparation publishes no preview or export")
	func cancelledPreparationLeavesSessionIdle() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let snapshot = try session.liveSnapshot()
		let url = try fixture.write(snapshot.encoded())
		let preparation = Task { await session.prepareImport(from: url) }
		preparation.cancel()
		await preparation.value
		#expect(session.preview == nil)
		#expect(!session.isBusy)
		#expect(session.errorMessage == nil)
		let export = Task { try await session.exportData() }
		export.cancel()
		await #expect(throws: CancellationError.self) { try await export.value }
		#expect(!session.isBusy)
		#expect(try session.liveSnapshot() == snapshot)
	}

	private func config(_ name: String) -> ServerConfig {
		var config = ServerConfig(connectionName: name)
		config.nickname = "TestNick"
		config.username = "test"
		config.realName = "Test User"
		config.awayNickname = ""
		config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test",
			serverPort: 6697,
			prefersSecuredConnection: true
		)]
		config.conversationList = [ConversationConfig(name: "#test")]
		return config
	}

	@Test("Complete XML export imports into independent container and standard stores, then recovers the backup")
	func twoStoreRoundTripAndRecovery() async throws {
		let source = try Fixture()
		let target = try Fixture()
		defer { source.cleanUp(); target.cleanUp() }
		let configuration = config("Source")
		source.stores.set(.array([.dictionary(configuration.dictionaryValue)]), for: SettingsKeys.Sessions.serverSessions)
		source.stores.set(false, for: SettingsKeys.Messages.showJoinLeave)
		source.stores.set(.array(["test-scheme"]), for: SettingsKeys.LinkSchemes.permitted)
		target.stores.set(true, for: SettingsKeys.LinkSchemes.permitAny)
		target.stores.set("keep this Mac's state", for: SettingsKeys.MainWindow.sidebarSelection)
		let originalSession = config("Target")
		target.stores.set(.array([.dictionary(originalSession.dictionaryValue)]), for: SettingsKeys.Sessions.serverSessions)
		let sourceSession = source.session()
		let targetSession = target.session()
		let original = try targetSession.liveSnapshot()
		let data = try await sourceSession.exportData()
		#expect(String(data: data.prefix(100), encoding: .utf8)?.contains("<?xml") == true)
		let decoded = try SettingsArchive.decode(data)
		#expect(decoded.values[SettingsKeys.Connection.confirmQuit.name] == true)
		#expect(decoded.unset.contains(SettingsKeys.LinkSchemes.permitAny.name) == false)
		#expect(decoded.values[SettingsKeys.LinkSchemes.permitAny.name] == nil)
		#expect(decoded.values[SettingsKeys.MainWindow.sidebarSelection.name] == nil)

		try await targetSession.prepareImport(from: source.write(data))
		#expect(targetSession.preview?.mode == .merge)
		let preview = try #require(targetSession.preview)
		#expect(preview.plan?.removedSessions.isEmpty == true)
		targetSession.previewMode = .restore
		#expect(targetSession.preview?.plan?.removedSessions == ["Target"])
		await targetSession.commitPreview()
		#expect(targetSession.errorMessage == nil)
		#expect(targetSession.result?.removedSessions == 1)
		#expect(try targetSession.liveSnapshot().hasSameConfiguration(as: sourceSession.liveSnapshot()))
		#expect(target.stores.standard.stringArray(forKey: SettingsKeys.LinkSchemes.permitted.name) == ["test-scheme"])
		#expect(target.stores.container.object(forKey: SettingsKeys.LinkSchemes.permitted.name) == nil)
		// Allowing every link scheme is this Mac's own decision, so Restore leaves it.
		#expect(target.stores.standard.bool(forKey: SettingsKeys.LinkSchemes.permitAny.name))
		#expect(target.stores.container
			.string(forKey: SettingsKeys.MainWindow.sidebarSelection.name) == "keep this Mac's state")
		let backup = try #require(targetSession.result?.backup)
		#expect(try await targetSession.recoveryStore.read(backup).hasSameConfiguration(as: original))
		await targetSession.prepareRecovery(backup)
		targetSession.previewMode = .restore
		await targetSession.commitPreview()
		#expect(try targetSession.liveSnapshot().hasSameConfiguration(as: original))
		#expect(targetSession.backups.count == 2)
	}

	@Test("One malformed field or inverted port pair prevents every write")
	func invalidWholeDocumentDoesNotMutate() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let before = try session.liveSnapshot()
		for invalid: [String: PropertyListValue] in [
			[SettingsKeys.Messages.showJoinLeave.name: false, SettingsKeys.Logging.scrollbackSaveLimit.name: "-7"],
			[SettingsKeys.Messages.showJoinLeave.name: false, SettingsKeys.FileTransfers.portRangeStart.name: 6000,
			 SettingsKeys.FileTransfers.portRangeEnd.name: 5000],
			[
				SettingsKeys.Messages.showJoinLeave.name: false,
				SettingsKeys.Sessions.serverSessions.name: .array([.dictionary([
					"uniqueIdentifier": "invalid", "serverList": "not an array",
				])]),
			],
		] {
			let data = try PropertyListSerialization.data(
				fromPropertyList: invalid.propertyListObject,
				format: .xml,
				options: 0
			)
			try await session.prepareImport(from: fixture.write(data))
			#expect(session.preview == nil)
			#expect(session.errorMessage != nil)
			#expect(try session.liveSnapshot() == before)
			#expect(session.backups.isEmpty)
		}
	}

	@Test("Failed backup and a stale preview refuse Restore without changing either store")
	func backupFailureAndStalePreviewPreventMutation() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let blockedDirectory = try fixture.write(Data())
		let session = fixture.session(backupDirectory: blockedDirectory)
		let before = try session.liveSnapshot()
		var archive = before
		archive.values[SettingsKeys.Messages.showJoinLeave.name] = false
		let url = try fixture.write(archive.encoded())
		await session.prepareImport(from: url)
		session.previewMode = .restore
		await session.commitPreview()
		#expect(session.errorMessage != nil)
		#expect(session.result == nil)
		#expect(try session.liveSnapshot() == before)
		let freshSession = fixture.session()
		await freshSession.prepareImport(from: url)
		fixture.stores.set(.array(["changed after preview"]), for: SettingsKeys.LinkSchemes.permitted)
		let changed = try freshSession.liveSnapshot()
		await freshSession.commitPreview()
		#expect(freshSession.result == nil)
		#expect(freshSession.errorMessage != nil)
		#expect(try freshSession.liveSnapshot() == changed)
	}

	@Test("Recovery retains five readable archives across new sessions")
	func recoveryRetention() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let snapshot = try session.liveSnapshot()
		for _ in 0 ..< 8 {
			_ = try await session.recoveryStore.save(snapshot)
		}
		let reopened = fixture.session()
		await reopened.refreshBackups()
		#expect(reopened.backups.count == 5)
		for backup in reopened.backups {
			#expect(try await reopened.recoveryStore.read(backup) == snapshot)
		}
	}

	@Test("Export strips pending secrets, certificates and connect commands without changing the source")
	func portableSessionsDoNotCarrySecrets() {
		var configuration = config("Private")
		configuration.pendingNicknamePassword = .set("nickname-password")
		configuration.pendingProxyPassword = .set("proxy-password")
		configuration.identityClientSideCertificate = Data("certificate-reference".utf8)
		configuration.loginCommands = ["msg NickServ identify secret"]
		configuration.serverList[0].pendingServerPassword = .set("server-password")
		configuration.conversationList[0].pendingSecretKey = .set("channel-password")
		let portable = SettingsSessionArchive.portable(configuration)
		#expect(portable.pendingNicknamePassword == .unchanged)
		#expect(portable.pendingProxyPassword == .unchanged)
		#expect(portable.identityClientSideCertificate == nil)
		#expect(portable.serverList[0].pendingServerPassword == .unchanged)
		#expect(portable.conversationList[0].pendingSecretKey == .unchanged)

		/* Connect commands are withheld by removing the key, never by writing an
		 empty list: an omitted list preserves the target's commands while an
		 included empty one clears them. */
		let commands = ServerConfig.CodingKeys.loginCommands.rawValue
		#expect(SettingsSessionArchive.portableDictionary(configuration)[commands] == nil)
		#expect(
			SettingsSessionArchive.portableDictionary(configuration, includeConnectCommands: true)[commands]
				== .array([.string("msg NickServ identify secret")])
		)

		#expect(configuration.loginCommands.count == 1)
		#expect(configuration.identityClientSideCertificate != nil)
	}

	@Test("Input size, depth, duplicate sessions and unsupported envelope versions are rejected")
	func boundedAndVersionedInput() throws {
		#expect(throws: SettingsTransferError.self) {
			try SettingsArchive.decode(Data(count: SettingsArchive.maximumBytes + 1))
		}
		var value: PropertyListValue = false
		for _ in 0 ..< 40 {
			value = .array([value])
		}
		let deep: [String: PropertyListValue] = ["deep": value]
		let data = try PropertyListSerialization.data(
			fromPropertyList: deep.propertyListObject,
			format: .binary,
			options: 0
		)
		#expect(throws: SettingsTransferError.self) { try SettingsArchive.decode(data) }
		let configuration = config("Duplicate").dictionaryValue
		#expect(throws: SettingsTransferError.self) {
			try SettingsSessionArchive.decode(.array([.dictionary(configuration), .dictionary(configuration)]))
		}
		let future: [String: PropertyListValue] = ["format": .string(SettingsArchive.format), "version": 999]
		let futureData = try PropertyListSerialization.data(
			fromPropertyList: future.propertyListObject,
			format: .xml,
			options: 0
		)
		#expect(throws: SettingsTransferError.self) { try SettingsArchive.decode(futureData) }
	}

	@Test("Number drafts commit only on explicit completion and report what the store refused")
	func transientNumberEditing() {
		var committed = "15000"
		let key = SettingsKeys.Logging.scrollbackSaveLimit
		let field = SettingsFieldValue(text: { committed }, write: { text in
			guard let value = UInt(text),
			      let plist = value.settingObject.flatMap(PropertyListValue.init(propertyList:)),
			      key.coerce(plist) != nil
			else { return false }
			committed = String(value)
			return true
		})
		var draft = SettingsFieldDraft()
		for input in ["", "1", "12", "123"] {
			draft.edit(input)
			#expect(committed == "15000")
			#expect(draft.displayed(committed) == input)
		}
		draft.commit(to: field)
		#expect(committed == "123")
		#expect(draft.wasRejected == false)
		#expect(draft.displayed(committed) == "123")
		draft.edit("-4")
		draft.commit(to: field)
		#expect(committed == "123")
		#expect(draft.wasRejected)
	}

	@Test("Theme fallback preserves unsupported bytes and all font fields follow the authoritative theme")
	func themeFallbackAndDerivedFont() throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		var future = TranscriptTheme.lines
		future.formatVersion = TranscriptTheme.currentFormatVersion + 1
		let data = try PropertyListEncoder().encode(future)
		fixture.stores.set(.data(data), for: SettingsKeys.Theme.transcriptTheme)
		let controller = ThemeStore(stores: fixture.stores)
		controller.reload()
		#expect(controller.theme == .lines)
		#expect(fixture.stores.container.data(forKey: SettingsKeys.Theme.transcriptTheme.name) == data)
		let roundTrip = try SettingsArchive.decode(SettingsArchive.snapshot(from: fixture.stores, sessions: []).encoded())
		#expect(roundTrip.values[SettingsKeys.Theme.transcriptTheme.name]?.data == data)
		let model = SettingsModel(themeStore: controller)
		var replacement = TranscriptTheme.bubbles
		replacement.fontSize = 24
		replacement.fontName = "Menlo"
		#expect(controller.apply(replacement))
		#expect(model.transcriptTheme.fontName == "Menlo")
		#expect(model.transcriptTheme.fontSize == 24)
		model.updateTheme { $0.name = "Edited from Settings" }
		#expect(controller.theme.fontName == "Menlo")
		#expect(controller.theme.fontSize == 24)
		#expect(controller.theme.name == "Edited from Settings")
	}

	/** The bounds a Settings field enforces are the key's own, so an imported
	 file cannot write a value the field would have refused. A privileged port a
	 sandboxed process cannot bind, and a scrollback limit outside what the
	 field has always accepted, are both rejected here rather than clamped. */
	@Test("Numeric declarations carry the bounds their fields enforce")
	func numericDeclarationConstraints() {
		#expect(SettingsKeys.Logging.scrollbackSaveLimit.coerce(100) != nil)
		#expect(SettingsKeys.Logging.scrollbackSaveLimit.coerce(50000) != nil)
		#expect(SettingsKeys.Logging.scrollbackSaveLimit.coerce(99) == nil)
		#expect(SettingsKeys.Logging.scrollbackSaveLimit.coerce(50001) == nil)
		#expect(SettingsKeys.Logging.scrollbackSaveLimit.coerce(0) == nil)
		#expect(SettingsKeys.Logging.scrollbackVisibleLimit.coerce(0) != nil)
		#expect(SettingsKeys.Logging.scrollbackVisibleLimit.coerce(50) == nil)
		#expect(SettingsKeys.Logging.scrollbackVisibleLimit.coerce(15000) != nil)
		#expect(SettingsKeys.Logging.scrollbackVisibleLimit.coerce(15001) == nil)
		#expect(SettingsKeys.Connection.autojoinDelayAfterIdentification.coerce(-1) == nil)
		#expect(SettingsKeys.FileTransfers.portRangeStart.coerce(1024) != nil)
		#expect(SettingsKeys.FileTransfers.portRangeStart.coerce(1023) == nil)
		#expect(SettingsKeys.FileTransfers.portRangeStart.coerce(0) == nil)
		#expect(SettingsKeys.FileTransfers.portRangeEnd.coerce(65535) != nil)
		#expect(SettingsKeys.FileTransfers.portRangeStart.isValid(
			5000,
			in: [SettingsKeys.FileTransfers.portRangeEnd.name: 4000]
		) == false)
		#expect(SettingsKeys.FileTransfers.portRangeEnd.isValid(
			4000,
			in: [SettingsKeys.FileTransfers.portRangeStart.name: 5000]
		) == false)
	}

	@Test("Imported servers have auto-connect cleared while the exported source is unchanged")
	func importedServersDoNotAutoConnect() throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		var configuration = config("Automatic source")
		configuration.autoConnect = true
		let source = SettingsArchive.snapshot(from: fixture.stores, sessions: [configuration])
		let archive = try SettingsArchive.decode(source.encoded())
		let plan = try SettingsTransferPlan(
			archive: archive,
			current: SettingsArchive.snapshot(from: fixture.stores, sessions: []),
			mode: .restore
		)
		#expect(source.sessions?.first?.autoConnect == true)
		#expect(plan.result.sessions?.first?.autoConnect == false)
	}

	@Test("Export failure is visible and user cancellation stays quiet")
	func exportErrorsAreVisible() throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		session.completeExport(.failure(CocoaError(.fileWriteNoPermission)))
		#expect(session.errorMessage != nil)
		#expect(session.completionMessage == nil)
		session.acknowledge()
		session.completeExport(.failure(CocoaError(.userCancelled)))
		#expect(session.errorMessage == nil)
	}

	@Test("Imported query retention is applied before model reconciliation and survives save/reopen",
	      arguments: [SettingsTransferMode.merge, .restore], [false, true])
	func rememberedQueriesSurviveModelImportSaveAndReopen(
		mode: SettingsTransferMode,
		existingSession: Bool
	) async throws {
		let source = try Fixture()
		let target = try Fixture()
		defer { source.cleanUp(); target.cleanUp() }
		source.stores.set(true, for: SettingsKeys.Appearance.rememberDirectConversations)
		target.stores.set(false, for: SettingsKeys.Appearance.rememberDirectConversations)
		var configuration = config("Remembered queries")
		let query = ConversationConfig(name: "RememberedPeer", type: .direct)
		configuration.conversationList.append(query)
		let sourceArchive = SettingsArchive.snapshot(from: source.stores, sessions: [configuration])
		let model = ChatEnvironmentFixture(settings: .current(stores: target.stores))
		if existingSession {
			var previous = configuration
			previous.conversationList.removeLast()
			_ = model.chatSession.createSession(with: previous)
		}
		#expect(!model.chatSession.environment.settings.remembersDirectConversations)
		let session = target.session(chatSession: model.chatSession)
		try await session.prepareImport(from: source.write(sourceArchive.encoded()))
		#expect(session.preview != nil)
		session.previewMode = mode
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		let live = try #require(model.chatSession.findSession(withId: configuration.uniqueIdentifier))
		#expect(live.environment.settings.remembersDirectConversations)
		#expect(live.conversationList.map(\.uniqueIdentifier) == configuration.conversationList.map(\.uniqueIdentifier))
		#expect(live.config.conversationList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
		let reopened = try target.reopenChatSession()
		let restored = try #require(reopened.chatSession.findSession(withId: configuration.uniqueIdentifier))
		#expect(restored.conversationList.map(\.uniqueIdentifier) == configuration.conversationList.map(\.uniqueIdentifier))
		#expect(restored.config.conversationList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
	}

	@Test("A query-policy-only Merge saves existing live queries on otherwise unchanged sessions")
	func queryPolicyOnlyImportRebuildsSavedLists() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		fixture.stores.set(false, for: SettingsKeys.Appearance.rememberDirectConversations)
		let model = ChatEnvironmentFixture(settings: .current(stores: fixture.stores))
		let live = model.chatSession.createSession(with: config("Existing live query"))
		let query = model.chatSession.createDirectConversation("ExistingPeer", on: live)
		#expect(!live.config.conversationList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
		let archive = SettingsArchive(
			values: [SettingsKeys.Appearance.rememberDirectConversations.name: true],
			unset: [],
			sessions: [live.config]
		)
		let session = fixture.session(chatSession: model.chatSession)
		try await session.prepareImport(from: fixture.write(archive.encoded()))
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(live.config.conversationList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
		let reopened = try fixture.reopenChatSession()
		let restored = try #require(reopened.chatSession.findSession(withId: live.uniqueIdentifier))
		#expect(restored.conversationList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
	}

	@Test("A removed server's protected backup restores commands and certificate references after save/reopen")
	func removedSessionRecoveryRestoresLocalAuthenticationConfiguration() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let model = ChatEnvironmentFixture(settings: .current(stores: fixture.stores))
		var configuration = config("Recover local authentication")
		configuration.loginCommands = ["mode +i"]
		configuration.identityClientSideCertificate = Data("fixture-certificate-reference".utf8)
		let original = model.chatSession.createSession(with: configuration)
		// Pending secret intent is deliberately not flushed to the Keychain or included in backups.
		original.config.pendingNicknamePassword = .set("fixture-pending-secret")
		let session = fixture.session(chatSession: model.chatSession)
		let removal = SettingsArchive.snapshot(from: fixture.stores, sessions: [])
		try await session.prepareImport(from: fixture.write(removal.encoded()))
		session.previewMode = .restore
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(model.chatSession.sessions.isEmpty)
		#expect(original.isTerminating)
		let backup = try #require(session.result?.backup)
		let permissions = try FileManager.default.attributesOfItem(atPath: backup.url.path)
		#expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600)
		let protected = try await session.recoveryStore.read(backup)
		#expect(protected.source == .localRecovery)
		#expect(protected.sessions?.first?.loginCommands == configuration.loginCommands)
		#expect(protected.sessions?.first?.identityClientSideCertificate == configuration.identityClientSideCertificate)
		#expect(protected.sessions?.first?.pendingNicknamePassword == .unchanged)
		let bytes = try Data(contentsOf: backup.url)
		#expect(String(data: bytes, encoding: .utf8)?.contains("fixture-pending-secret") == false)
		#expect(throws: SettingsTransferError.self) { try SettingsArchive.decode(bytes) }

		let afterRemoval = try fixture.reopenChatSession()
		#expect(afterRemoval.chatSession.sessions.isEmpty)
		let recovery = fixture.session(chatSession: afterRemoval.chatSession)
		await recovery.prepareRecovery(backup)
		#expect(recovery.preview?.archive.source == .localRecovery)
		recovery.previewMode = .restore
		await recovery.commitPreview()
		#expect(recovery.errorMessage == nil)
		let restored = try #require(afterRemoval.chatSession.findSession(withId: configuration.uniqueIdentifier))
		#expect(restored !== original)
		#expect(restored.config.loginCommands == configuration.loginCommands)
		#expect(restored.config.identityClientSideCertificate == configuration.identityClientSideCertificate)
		#expect(!restored.config.autoConnect && !restored.isConnected && !restored.isConnecting)
		let reopened = try fixture.reopenChatSession()
		let persisted = try #require(reopened.chatSession.findSession(withId: configuration.uniqueIdentifier))
		#expect(persisted.config.loginCommands == configuration.loginCommands)
		#expect(persisted.config.identityClientSideCertificate == configuration.identityClientSideCertificate)

		let portable = try await SettingsArchive.decode(recovery.exportData())
		#expect(portable.omittedConnectCommands.contains(configuration.uniqueIdentifier))
		#expect(portable.sessions?.first?.loginCommands.isEmpty == true)
		#expect(portable.sessions?.first?.identityClientSideCertificate == nil)
		let optIn = try await SettingsArchive.decode(recovery.exportData(includeConnectCommands: true))
		#expect(optIn.sessions?.first?.loginCommands == configuration.loginCommands)
		#expect(optIn.sessions?.first?.identityClientSideCertificate == nil)
	}

	@Test("Portable omission preserves commands, but included lists and explicit empty lists replace them",
	      arguments: [false, true], [false, true])
	func portableCommandPresenceControlsModelUpdates(includeCommands: Bool, emptyCommands: Bool) async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		var original = config("Command presence")
		original.loginCommands = ["mode +i"]
		original.identityClientSideCertificate = Data("existing-local-reference".utf8)
		let model = ChatEnvironmentFixture(settings: .current(stores: fixture.stores))
		let live = model.chatSession.createSession(with: original)
		var imported = original
		imported.loginCommands = emptyCommands ? [] : ["whois TestNick"]
		imported.identityClientSideCertificate = Data("must-not-import-reference".utf8)
		let archive = SettingsArchive.snapshot(from: fixture.stores, sessions: [imported])
		let session = fixture.session(chatSession: model.chatSession)
		let data = try archive.encoded(includeConnectCommands: includeCommands)
		let decoded = try SettingsArchive.decode(data)
		#expect(decoded.omittedConnectCommands.contains(original.uniqueIdentifier) == !includeCommands)
		try await session.prepareImport(from: fixture.write(data))
		session.previewMode = .restore
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		let expected = includeCommands ? imported.loginCommands : original.loginCommands
		#expect(live.config.loginCommands == expected)
		#expect(live.config.identityClientSideCertificate == original.identityClientSideCertificate)
		let reopened = try fixture.reopenChatSession()
		#expect(reopened.chatSession.sessions.first?.config.loginCommands == expected)
	}

	@Test("Only private files in the owned backup folder can enter local recovery")
	func recoveryRejectsExternalOrUnprotectedFiles() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let backup = try await session.recoveryStore.save(SettingsArchive.snapshot(
			from: fixture.stores,
			sessions: [config("Protected")]
		))
		let external = try fixture.write(Data(contentsOf: backup.url))
		let forged = SettingsRecoveryBackup(url: external, created: Date())
		await #expect(throws: SettingsTransferError.self) { try await session.recoveryStore.read(forged) }
		try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: backup.url.path)
		await #expect(throws: CocoaError.self) { try await session.recoveryStore.read(backup) }
	}

	@Test("Local recovery restores explicit empty commands and an absent certificate reference")
	func localRecoveryCanClearAuthenticationConfiguration() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let original = config("Empty local authentication configuration")
		let model = ChatEnvironmentFixture(settings: .current(stores: fixture.stores))
		let session = fixture.session(chatSession: model.chatSession)
		let backup = try await session.recoveryStore.save(SettingsArchive.snapshot(from: fixture.stores, sessions: [original]))
		var changed = original
		changed.loginCommands = ["mode +i"]
		changed.identityClientSideCertificate = Data("subsequently-added-reference".utf8)
		let live = model.chatSession.createSession(with: changed)
		await session.prepareRecovery(backup)
		session.previewMode = .restore
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(live.config.loginCommands.isEmpty)
		#expect(live.config.identityClientSideCertificate == nil)
		let reopened = try fixture.reopenChatSession()
		#expect(reopened.chatSession.sessions.first?.config.loginCommands.isEmpty == true)
		#expect(reopened.chatSession.sessions.first?.config.identityClientSideCertificate == nil)
	}

	@Test("Changes to local commands or certificate references invalidate an outstanding import preview")
	func localAuthenticationChangesInvalidatePreview() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let model = ChatEnvironmentFixture(settings: .current(stores: fixture.stores))
		let live = model.chatSession.createSession(with: config("Changed local authentication"))
		let session = fixture.session(chatSession: model.chatSession)
		var archive = try session.liveSnapshot()
		archive.values[SettingsKeys.Messages.showJoinLeave.name] = false
		try await session.prepareImport(from: fixture.write(archive.encoded()))
		live.config.loginCommands = ["mode +i"]
		live.config.identityClientSideCertificate = Data("changed-while-previewing".utf8)
		await session.commitPreview()
		#expect(session.result == nil)
		#expect(session.errorMessage != nil)
		#expect(live.config.loginCommands == ["mode +i"])
		#expect(live.config.identityClientSideCertificate == Data("changed-while-previewing".utf8))
		#expect(fixture.stores[SettingsKeys.Messages.showJoinLeave])
	}
}

extension SettingsTransferTests {
	@Test("Restore removes extra live and saved queries without deleting local data", arguments: [false, true])
	func restoreRemovesExtraQueries(rememberDirectConversations: Bool) async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		fixture.stores.set(.boolean(rememberDirectConversations), for: SettingsKeys.Appearance.rememberDirectConversations)
		let model = ChatEnvironmentFixture(settings: .current(stores: fixture.stores))
		let live = model.chatSession.createSession(with: config("Exact query restore"))
		let session = fixture.session(chatSession: model.chatSession)
		let original = try session.liveSnapshot()
		let backup = try await session.recoveryStore.save(original)
		let extra = model.chatSession.createDirectConversation("ExtraPeer", on: live)
		let presentation = RemovalPresentation()
		extra.presentation = presentation
		let extraConfiguration = extra.config
		#expect(live.conversationList.contains { $0 === extra })
		#expect(live.config.conversationList.contains { $0.uniqueIdentifier == extra.uniqueIdentifier } == rememberDirectConversations)

		await session.prepareRecovery(backup)
		session.previewMode = .restore
		await session.commitPreview()

		#expect(session.errorMessage == nil)
		#expect(session.result != nil)
		let restoredSnapshot = try session.liveSnapshot()
		#expect(Set(restoredSnapshot.values.keys).union(original.values.keys).filter {
			restoredSnapshot.values[$0] != original.values[$0]
		}.sorted().isEmpty)
		#expect(restoredSnapshot.unset == original.unset)
		let restoredSession = try #require(restoredSnapshot.sessions?.first).dictionaryValue
		let originalSession = try #require(original.sessions?.first).dictionaryValue
		#expect(Set(restoredSession.keys).union(originalSession.keys).filter {
			restoredSession[$0] != originalSession[$0]
		}.sorted().isEmpty)
		#expect(restoredSnapshot.hasSameConfiguration(as: original))
		#expect(live.conversationList.map(\.uniqueIdentifier) == original.sessions?.first?.conversationList
			.map(\.uniqueIdentifier))
		#expect(!live.config.conversationList.contains { $0.uniqueIdentifier == extra.uniqueIdentifier })
		#expect(extra.status == .terminated)
		#expect(extra.config == extraConfiguration)
		#expect(presentation.preservedRemovals == 1)
		#expect(presentation.permanentRemovals == 0)
		#expect(presentation.applicationTerminations == 0)
		let reopened = try fixture.reopenChatSession()
		let restored = try #require(reopened.chatSession.findSession(withId: live.uniqueIdentifier))
		#expect(restored.conversationList.map(\.uniqueIdentifier) == live.conversationList.map(\.uniqueIdentifier))
		#expect(!restored.config.conversationList.contains { $0.uniqueIdentifier == extra.uniqueIdentifier })
	}
}
