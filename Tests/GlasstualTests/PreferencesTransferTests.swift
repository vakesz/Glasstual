/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import SwiftUI
import Testing

@MainActor
@Suite("Configuration transfer and recovery")
struct PreferencesTransferTests {
	private typealias Fixture = PreferencesTransferFixture

	private func client(_ name: String) -> ClientConfig {
		var config = ClientConfig(connectionName: name)
		config.nickname = "TestNick"
		config.username = "test"
		config.realName = "Test User"
		config.awayNickname = ""
		config.serverList = [Server(
			serverAddress: "irc.example.test",
			serverPort: 6697,
			prefersSecuredConnection: true
		)]
		config.channelList = [ChannelConfig(channelName: "#test")]
		return config
	}

	@Test("Complete XML export imports into independent container and standard stores, then recovers the backup")
	func twoStoreRoundTripAndRecovery() async throws {
		let source = try Fixture()
		let target = try Fixture()
		defer { source.cleanUp(); target.cleanUp() }
		let configuration = client("Source")
		source.stores.set(.array([.dictionary(configuration.dictionaryValue)]), for: Preferences.Connection.clientList)
		source.stores.set(false, for: Preferences.Messages.showJoinLeave)
		source.stores.set(.array(["test-scheme"]), for: Preferences.LinkSchemes.permitted)
		target.stores.set(true, for: Preferences.LinkSchemes.permitAny)
		target.stores.set("keep this Mac's state", for: Preferences.MainWindow.serverListSelection)
		let originalClient = client("Target")
		target.stores.set(.array([.dictionary(originalClient.dictionaryValue)]), for: Preferences.Connection.clientList)
		let sourceSession = source.session()
		let targetSession = target.session()
		let original = try targetSession.liveSnapshot()
		let data = try await sourceSession.exportData()
		#expect(String(data: data.prefix(100), encoding: .utf8)?.contains("<?xml") == true)
		let decoded = try PreferencesArchive.decode(data)
		#expect(decoded.values[Preferences.Connection.confirmQuit.name] == true)
		#expect(decoded.unset.contains(Preferences.LinkSchemes.permitAny.name))
		#expect(decoded.values[Preferences.MainWindow.serverListSelection.name] == nil)

		try await targetSession.prepareImport(from: source.write(data))
		#expect(targetSession.preview?.mode == .merge)
		let preview = try #require(targetSession.preview)
		#expect(preview.plan?.removedClients.isEmpty == true)
		targetSession.previewMode = .restore
		#expect(targetSession.preview?.plan?.removedClients == ["Target"])
		await targetSession.commitPreview()
		#expect(targetSession.errorMessage == nil)
		#expect(targetSession.result?.removedClients == 1)
		#expect(try targetSession.liveSnapshot().hasSameConfiguration(as: sourceSession.liveSnapshot()))
		#expect(target.stores.standard.stringArray(forKey: Preferences.LinkSchemes.permitted.name) == ["test-scheme"])
		#expect(target.stores.container.object(forKey: Preferences.LinkSchemes.permitted.name) == nil)
		#expect(target.stores.standard.object(forKey: Preferences.LinkSchemes.permitAny.name) == nil)
		#expect(target.stores.container
			.string(forKey: Preferences.MainWindow.serverListSelection.name) == "keep this Mac's state")
		let backup = try #require(targetSession.result?.backup)
		#expect(try await targetSession.recoveryStore.read(backup).hasSameConfiguration(as: original))
		await targetSession.prepareRecovery(backup)
		targetSession.previewMode = .restore
		await targetSession.commitPreview()
		#expect(try targetSession.liveSnapshot().hasSameConfiguration(as: original))
		#expect(targetSession.backups.count == 2)
	}

	@Test("Legacy sparse Merge keeps absent settings and other servers, and cannot Restore")
	func legacyMergeIsNonDestructive() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let existing = client("Existing")
		fixture.stores.set(.array([.dictionary(existing.dictionaryValue)]), for: Preferences.Connection.clientList)
		fixture.stores.set(.array(["kept"]), for: Preferences.LinkSchemes.permitted)
		let legacy: [String: PropertyListValue] = [Preferences.Messages.showJoinLeave.name: false]
		let data = try PropertyListSerialization.data(
			fromPropertyList: legacy.propertyListObject,
			format: .binary,
			options: 0
		)
		let session = fixture.session()
		try await session.prepareImport(from: fixture.write(data))
		let preview = try #require(session.preview)
		#expect(!preview.archive.isComplete)
		#expect(throws: PreferencesTransferError.self) {
			try PreferencesTransferPlan(archive: preview.archive, current: preview.current, mode: .restore)
		}
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(fixture.stores.container.bool(forKey: Preferences.Messages.showJoinLeave.name) == false)
		#expect(fixture.stores.standard.stringArray(forKey: Preferences.LinkSchemes.permitted.name) == ["kept"])
		#expect(try session.liveSnapshot().clients?.map(\.uniqueIdentifier) == [existing.uniqueIdentifier])
	}

	@Test("One malformed field or inverted port pair prevents every write")
	func invalidWholeDocumentDoesNotMutate() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let before = try session.liveSnapshot()
		for invalid: [String: PropertyListValue] in [
			[Preferences.Messages.showJoinLeave.name: false, Preferences.Logging.scrollbackSaveLimit.name: "-7"],
			[Preferences.Messages.showJoinLeave.name: false, Preferences.FileTransfers.portRangeStart.name: 6000,
			 Preferences.FileTransfers.portRangeEnd.name: 5000],
			[
				Preferences.Messages.showJoinLeave.name: false,
				Preferences.Connection.clientList.name: .array([.dictionary([
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
		archive.values[Preferences.Messages.showJoinLeave.name] = false
		let url = try fixture.write(archive.encoded())
		await session.prepareImport(from: url)
		session.previewMode = .restore
		await session.commitPreview()
		#expect(session.errorMessage != nil)
		#expect(session.result == nil)
		#expect(try session.liveSnapshot() == before)
		let freshSession = fixture.session()
		await freshSession.prepareImport(from: url)
		fixture.stores.set(.array(["changed after preview"]), for: Preferences.LinkSchemes.permitted)
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
	func portableClientsDoNotCarrySecrets() {
		var configuration = client("Private")
		configuration.pendingNicknamePassword = .set("nickname-password")
		configuration.pendingProxyPassword = .set("proxy-password")
		configuration.identityClientSideCertificate = Data("certificate-reference".utf8)
		configuration.loginCommands = ["msg NickServ identify secret"]
		configuration.serverList[0].pendingServerPassword = .set("server-password")
		configuration.channelList[0].pendingSecretKey = "channel-password"
		let portable = PreferencesClientArchive.portable(configuration)
		#expect(portable.pendingNicknamePassword == .unchanged)
		#expect(portable.pendingProxyPassword == .unchanged)
		#expect(portable.identityClientSideCertificate == nil)
		#expect(portable.serverList[0].pendingServerPassword == .unchanged)
		#expect(portable.channelList[0].pendingSecretKey == nil)

		/* Connect commands are withheld by removing the key, never by writing an
		 empty list: an omitted list preserves the target's commands while an
		 included empty one clears them. */
		let commands = ClientConfig.CodingKeys.loginCommands.rawValue
		#expect(PreferencesClientArchive.portableDictionary(configuration)[commands] == nil)
		#expect(
			PreferencesClientArchive.portableDictionary(configuration, includeConnectCommands: true)[commands]
				== .array([.string("msg NickServ identify secret")])
		)

		#expect(configuration.loginCommands.count == 1)
		#expect(configuration.identityClientSideCertificate != nil)
	}

	@Test("Input size, depth, duplicate clients and unsupported envelope versions are rejected")
	func boundedAndVersionedInput() throws {
		#expect(throws: PreferencesTransferError.self) {
			try PreferencesArchive.decode(Data(count: PreferencesArchive.maximumBytes + 1))
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
		#expect(throws: PreferencesTransferError.self) { try PreferencesArchive.decode(data) }
		let configuration = client("Duplicate").dictionaryValue
		#expect(throws: PreferencesTransferError.self) {
			try PreferencesClientArchive.decode(.array([.dictionary(configuration), .dictionary(configuration)]))
		}
		let future: [String: PropertyListValue] = ["format": .string(PreferencesArchive.format), "version": 999]
		let futureData = try PropertyListSerialization.data(
			fromPropertyList: future.propertyListObject,
			format: .xml,
			options: 0
		)
		#expect(throws: PreferencesTransferError.self) { try PreferencesArchive.decode(futureData) }
	}

	@Test("Number drafts commit only on explicit completion and reject invalid edits")
	func transientNumberEditing() {
		var committed = "15000"
		let key = Preferences.Logging.scrollbackSaveLimit
		let binding = Binding(get: { committed }, set: { text in
			if let value = UInt(text),
			   let plist = value.preferenceObject.flatMap(PropertyListValue.init(propertyList:)),
			   key.coerce(plist) != nil
			{
				committed = String(value)
			}
		})
		var draft = PreferencesNumberDraft()
		for input in ["", "1", "12", "123"] {
			draft.text = input
			#expect(committed == "15000")
		}
		draft.commit(to: binding)
		#expect(committed == "123")
		#expect(!draft.rejected)
		draft.text = "-4"
		draft.commit(to: binding)
		#expect(committed == "123")
		#expect(draft.rejected)
	}

	@Test("Theme fallback preserves unsupported bytes and all font fields follow the authoritative theme")
	func themeFallbackAndDerivedFont() throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		var future = TranscriptTheme.lines
		future.formatVersion = TranscriptTheme.currentFormatVersion + 1
		let data = try PropertyListEncoder().encode(future)
		fixture.stores.set(.data(data), for: Preferences.Theme.transcriptTheme)
		let controller = ThemeController(stores: fixture.stores)
		controller.reload()
		#expect(controller.theme == .lines)
		#expect(fixture.stores.container.data(forKey: Preferences.Theme.transcriptTheme.name) == data)
		let roundTrip = try PreferencesArchive.decode(fixture.stores.snapshot(clients: []).encoded())
		#expect(roundTrip.values[Preferences.Theme.transcriptTheme.name]?.data == data)
		let model = PreferencesPaneModel(themeController: controller)
		var replacement = TranscriptTheme.bubbles
		replacement.fontSize = 24
		replacement.fontName = "Menlo"
		#expect(controller.apply(replacement))
		#expect(model.channelViewFontName == "Menlo")
		#expect(model.channelViewFontSize == 24)
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
		#expect(Preferences.Logging.scrollbackSaveLimit.coerce(100) != nil)
		#expect(Preferences.Logging.scrollbackSaveLimit.coerce(50000) != nil)
		#expect(Preferences.Logging.scrollbackSaveLimit.coerce(99) == nil)
		#expect(Preferences.Logging.scrollbackSaveLimit.coerce(50001) == nil)
		#expect(Preferences.Logging.scrollbackSaveLimit.coerce(0) == nil)
		#expect(Preferences.Logging.scrollbackVisibleLimit.coerce(0) != nil)
		#expect(Preferences.Logging.scrollbackVisibleLimit.coerce(50) == nil)
		#expect(Preferences.Logging.scrollbackVisibleLimit.coerce(15000) != nil)
		#expect(Preferences.Logging.scrollbackVisibleLimit.coerce(15001) == nil)
		#expect(Preferences.Connection.autojoinDelayAfterIdentification.coerce(-1) == nil)
		#expect(Preferences.FileTransfers.portRangeStart.coerce(1024) != nil)
		#expect(Preferences.FileTransfers.portRangeStart.coerce(1023) == nil)
		#expect(Preferences.FileTransfers.portRangeStart.coerce(0) == nil)
		#expect(Preferences.FileTransfers.portRangeEnd.coerce(65535) != nil)
		#expect(Preferences.FileTransfers.portRangeStart.isValid(
			5000,
			in: [Preferences.FileTransfers.portRangeEnd.name: 4000]
		) == false)
		#expect(Preferences.FileTransfers.portRangeEnd.isValid(
			4000,
			in: [Preferences.FileTransfers.portRangeStart.name: 5000]
		) == false)
	}

	@Test("Plugin pane identities do not depend on their position in the loaded inventory")
	func stablePluginPaneIdentity() {
		let bundle = "com.example.preference-plugin"
		let identifier = PreferencesPaneCatalog.pluginIdentifier(bundleIdentifier: bundle)
		#expect(PreferencesPaneCatalog.pluginBundleIdentifier(from: identifier) == bundle)
		#expect(PreferencesPaneCatalog.pluginBundleIdentifier(from: "plugin:") == nil)
		#expect(PreferencesPaneCatalog.pluginBundleIdentifier(from: "plugin-0") == nil)
	}

	@Test("Imported servers have auto-connect cleared while the exported source is unchanged")
	func importedServersDoNotAutoConnect() throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		var configuration = client("Automatic source")
		configuration.autoConnect = true
		let source = fixture.stores.snapshot(clients: [configuration])
		let archive = try PreferencesArchive.decode(source.encoded())
		let plan = try PreferencesTransferPlan(
			archive: archive,
			current: fixture.stores.snapshot(clients: []),
			mode: .restore
		)
		#expect(source.clients?.first?.autoConnect == true)
		#expect(plan.result.clients?.first?.autoConnect == false)
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
	      arguments: [PreferencesTransferMode.merge, .restore], [false, true])
	func rememberedQueriesSurviveModelImportSaveAndReopen(
		mode: PreferencesTransferMode,
		existingClient: Bool
	) async throws {
		let source = try Fixture()
		let target = try Fixture()
		defer { source.cleanUp(); target.cleanUp() }
		source.stores.set(true, for: Preferences.Appearance.rememberQueryStates)
		target.stores.set(false, for: Preferences.Appearance.rememberQueryStates)
		var configuration = client("Remembered queries")
		let query = ChannelConfig(channelName: "RememberedPeer", type: .privateMessage)
		configuration.channelList.append(query)
		let sourceArchive = source.stores.snapshot(clients: [configuration])
		let model = GLTClientEnvironmentFixture(preferences: .current(stores: target.stores))
		if existingClient {
			var previous = configuration
			previous.channelList.removeLast()
			_ = model.world.createClient(with: previous)
		}
		#expect(!model.world.environment.preferences.rememberServerListQueryStates)
		let session = target.session(world: model.world)
		try await session.prepareImport(from: source.write(sourceArchive.encoded()))
		#expect(session.preview != nil)
		session.previewMode = mode
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		let live = try #require(model.world.findClient(withId: configuration.uniqueIdentifier))
		#expect(live.environment.preferences.rememberServerListQueryStates)
		#expect(live.channelList.map(\.uniqueIdentifier) == configuration.channelList.map(\.uniqueIdentifier))
		#expect(live.config.channelList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
		let reopened = try target.reopenWorld()
		let restored = try #require(reopened.world.findClient(withId: configuration.uniqueIdentifier))
		#expect(restored.channelList.map(\.uniqueIdentifier) == configuration.channelList.map(\.uniqueIdentifier))
		#expect(restored.config.channelList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
	}

	@Test("A query-policy-only Merge saves existing live queries on otherwise unchanged clients")
	func queryPolicyOnlyImportRebuildsSavedLists() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		fixture.stores.set(false, for: Preferences.Appearance.rememberQueryStates)
		let model = GLTClientEnvironmentFixture(preferences: .current(stores: fixture.stores))
		let live = model.world.createClient(with: client("Existing live query"))
		let query = model.world.createPrivateMessage("ExistingPeer", on: live)
		#expect(!live.config.channelList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
		let legacy: [String: PropertyListValue] = [Preferences.Appearance.rememberQueryStates.name: true]
		let data = try PropertyListSerialization.data(
			fromPropertyList: legacy.propertyListObject,
			format: .xml,
			options: 0
		)
		let session = fixture.session(world: model.world)
		try await session.prepareImport(from: fixture.write(data))
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(live.config.channelList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
		let reopened = try fixture.reopenWorld()
		let restored = try #require(reopened.world.findClient(withId: live.uniqueIdentifier))
		#expect(restored.channelList.contains { $0.uniqueIdentifier == query.uniqueIdentifier })
	}

	@Test("A removed server's protected backup restores commands and certificate references after save/reopen")
	func removedClientRecoveryRestoresLocalAuthenticationConfiguration() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let model = GLTClientEnvironmentFixture(preferences: .current(stores: fixture.stores))
		var configuration = client("Recover local authentication")
		configuration.loginCommands = ["mode +i"]
		configuration.identityClientSideCertificate = Data("fixture-certificate-reference".utf8)
		let original = model.world.createClient(with: configuration)
		// Pending secret intent is deliberately not flushed to the Keychain or included in backups.
		original.config.pendingNicknamePassword = .set("fixture-pending-secret")
		let session = fixture.session(world: model.world)
		let removal = fixture.stores.snapshot(clients: [])
		try await session.prepareImport(from: fixture.write(removal.encoded()))
		session.previewMode = .restore
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(model.world.clientList.isEmpty)
		#expect(original.isTerminating)
		let backup = try #require(session.result?.backup)
		let permissions = try FileManager.default.attributesOfItem(atPath: backup.url.path)
		#expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o600)
		let protected = try await session.recoveryStore.read(backup)
		#expect(protected.source == .localRecovery)
		#expect(protected.clients?.first?.loginCommands == configuration.loginCommands)
		#expect(protected.clients?.first?.identityClientSideCertificate == configuration.identityClientSideCertificate)
		#expect(protected.clients?.first?.pendingNicknamePassword == .unchanged)
		let bytes = try Data(contentsOf: backup.url)
		#expect(String(data: bytes, encoding: .utf8)?.contains("fixture-pending-secret") == false)
		#expect(throws: PreferencesTransferError.self) { try PreferencesArchive.decode(bytes) }

		let afterRemoval = try fixture.reopenWorld()
		#expect(afterRemoval.world.clientList.isEmpty)
		let recovery = fixture.session(world: afterRemoval.world)
		await recovery.prepareRecovery(backup)
		#expect(recovery.preview?.archive.source == .localRecovery)
		recovery.previewMode = .restore
		await recovery.commitPreview()
		#expect(recovery.errorMessage == nil)
		let restored = try #require(afterRemoval.world.findClient(withId: configuration.uniqueIdentifier))
		#expect(restored !== original)
		#expect(restored.config.loginCommands == configuration.loginCommands)
		#expect(restored.config.identityClientSideCertificate == configuration.identityClientSideCertificate)
		#expect(!restored.config.autoConnect && !restored.isConnected && !restored.isConnecting)
		let reopened = try fixture.reopenWorld()
		let persisted = try #require(reopened.world.findClient(withId: configuration.uniqueIdentifier))
		#expect(persisted.config.loginCommands == configuration.loginCommands)
		#expect(persisted.config.identityClientSideCertificate == configuration.identityClientSideCertificate)

		let portable = try await PreferencesArchive.decode(recovery.exportData())
		#expect(portable.omittedConnectCommands.contains(configuration.uniqueIdentifier))
		#expect(portable.clients?.first?.loginCommands.isEmpty == true)
		#expect(portable.clients?.first?.identityClientSideCertificate == nil)
		let optIn = try await PreferencesArchive.decode(recovery.exportData(includeConnectCommands: true))
		#expect(optIn.clients?.first?.loginCommands == configuration.loginCommands)
		#expect(optIn.clients?.first?.identityClientSideCertificate == nil)
	}

	@Test("Portable omission preserves commands, but included lists and explicit empty lists replace them",
	      arguments: [false, true], [false, true])
	func portableCommandPresenceControlsModelUpdates(includeCommands: Bool, emptyCommands: Bool) async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		var original = client("Command presence")
		original.loginCommands = ["mode +i"]
		original.identityClientSideCertificate = Data("existing-local-reference".utf8)
		let model = GLTClientEnvironmentFixture(preferences: .current(stores: fixture.stores))
		let live = model.world.createClient(with: original)
		var imported = original
		imported.loginCommands = emptyCommands ? [] : ["whois TestNick"]
		imported.identityClientSideCertificate = Data("must-not-import-reference".utf8)
		let archive = fixture.stores.snapshot(clients: [imported])
		let session = fixture.session(world: model.world)
		let data = try archive.encoded(includeConnectCommands: includeCommands)
		let decoded = try PreferencesArchive.decode(data)
		#expect(decoded.omittedConnectCommands.contains(original.uniqueIdentifier) == !includeCommands)
		try await session.prepareImport(from: fixture.write(data))
		session.previewMode = .restore
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		let expected = includeCommands ? imported.loginCommands : original.loginCommands
		#expect(live.config.loginCommands == expected)
		#expect(live.config.identityClientSideCertificate == original.identityClientSideCertificate)
		let reopened = try fixture.reopenWorld()
		#expect(reopened.world.clientList.first?.config.loginCommands == expected)
	}

	@Test("Legacy commands remain included, while a missing legacy command key preserves local commands",
	      arguments: [false, true])
	func legacyCommandPresenceIsPreserved(omitted: Bool) async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		var original = client("Legacy commands")
		original.loginCommands = ["mode +i"]
		let model = GLTClientEnvironmentFixture(preferences: .current(stores: fixture.stores))
		let live = model.world.createClient(with: original)
		var imported = original
		imported.loginCommands = ["whois TestNick"]
		var dictionary = imported.dictionaryValue
		if omitted {
			dictionary.removeValue(forKey: ClientConfig.CodingKeys.loginCommands.rawValue)
		}
		let legacy: [String: PropertyListValue] =
			[Preferences.Connection.clientList.name: .array([.dictionary(dictionary)])]
		let data = try PropertyListSerialization.data(
			fromPropertyList: legacy.propertyListObject,
			format: .xml,
			options: 0
		)
		let session = fixture.session(world: model.world)
		try await session.prepareImport(from: fixture.write(data))
		#expect(session.preview?.archive.isComplete == false)
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(live.config.loginCommands == (omitted ? original.loginCommands : imported.loginCommands))
	}

	@Test("Only private files in the owned backup folder can enter local recovery")
	func recoveryRejectsExternalOrUnprotectedFiles() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let backup = try await session.recoveryStore.save(fixture.stores.snapshot(clients: [client("Protected")]))
		let external = try fixture.write(Data(contentsOf: backup.url))
		let forged = PreferencesRecoveryBackup(url: external, created: Date())
		await #expect(throws: PreferencesTransferError.self) { try await session.recoveryStore.read(forged) }
		try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: backup.url.path)
		await #expect(throws: CocoaError.self) { try await session.recoveryStore.read(backup) }
	}

	@Test("Local recovery restores explicit empty commands and an absent certificate reference")
	func localRecoveryCanClearAuthenticationConfiguration() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let original = client("Empty local authentication configuration")
		let model = GLTClientEnvironmentFixture(preferences: .current(stores: fixture.stores))
		let session = fixture.session(world: model.world)
		let backup = try await session.recoveryStore.save(fixture.stores.snapshot(clients: [original]))
		var changed = original
		changed.loginCommands = ["mode +i"]
		changed.identityClientSideCertificate = Data("subsequently-added-reference".utf8)
		let live = model.world.createClient(with: changed)
		await session.prepareRecovery(backup)
		session.previewMode = .restore
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(live.config.loginCommands.isEmpty)
		#expect(live.config.identityClientSideCertificate == nil)
		let reopened = try fixture.reopenWorld()
		#expect(reopened.world.clientList.first?.config.loginCommands.isEmpty == true)
		#expect(reopened.world.clientList.first?.config.identityClientSideCertificate == nil)
	}

	@Test("Changes to local commands or certificate references invalidate an outstanding import preview")
	func localAuthenticationChangesInvalidatePreview() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let model = GLTClientEnvironmentFixture(preferences: .current(stores: fixture.stores))
		let live = model.world.createClient(with: client("Changed local authentication"))
		let session = fixture.session(world: model.world)
		var archive = try session.liveSnapshot()
		archive.values[Preferences.Messages.showJoinLeave.name] = false
		try await session.prepareImport(from: fixture.write(archive.encoded()))
		live.config.loginCommands = ["mode +i"]
		live.config.identityClientSideCertificate = Data("changed-while-previewing".utf8)
		await session.commitPreview()
		#expect(session.result == nil)
		#expect(session.errorMessage != nil)
		#expect(live.config.loginCommands == ["mode +i"])
		#expect(live.config.identityClientSideCertificate == Data("changed-while-previewing".utf8))
		#expect(fixture.stores[Preferences.Messages.showJoinLeave])
	}
}

extension PreferencesTransferTests {
	@Test("Restore removes extra live and saved queries without deleting local data", arguments: [false, true])
	func restoreRemovesExtraQueries(rememberQueries: Bool) async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		fixture.stores.set(.boolean(rememberQueries), for: Preferences.Appearance.rememberQueryStates)
		let model = GLTClientEnvironmentFixture(preferences: .current(stores: fixture.stores))
		let live = model.world.createClient(with: client("Exact query restore"))
		let session = fixture.session(world: model.world)
		let original = try session.liveSnapshot()
		let backup = try await session.recoveryStore.save(original)
		let extra = model.world.createPrivateMessage("ExtraPeer", on: live)
		let presentation = RemovalPresentation()
		extra.presentation = presentation
		let extraConfiguration = extra.config
		#expect(live.channelList.contains { $0 === extra })
		#expect(live.config.channelList.contains { $0.uniqueIdentifier == extra.uniqueIdentifier } == rememberQueries)

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
		let restoredClient = try #require(restoredSnapshot.clients?.first).dictionaryValue
		let originalClient = try #require(original.clients?.first).dictionaryValue
		#expect(Set(restoredClient.keys).union(originalClient.keys).filter {
			restoredClient[$0] != originalClient[$0]
		}.sorted().isEmpty)
		#expect(restoredSnapshot.hasSameConfiguration(as: original))
		#expect(live.channelList.map(\.uniqueIdentifier) == original.clients?.first?.channelList
			.map(\.uniqueIdentifier))
		#expect(!live.config.channelList.contains { $0.uniqueIdentifier == extra.uniqueIdentifier })
		#expect(extra.status == .terminated)
		#expect(extra.config == extraConfiguration)
		#expect(presentation.preservedRemovals == 1)
		#expect(presentation.permanentRemovals == 0)
		#expect(presentation.applicationTerminations == 0)
		let reopened = try fixture.reopenWorld()
		let restored = try #require(reopened.world.findClient(withId: live.uniqueIdentifier))
		#expect(restored.channelList.map(\.uniqueIdentifier) == live.channelList.map(\.uniqueIdentifier))
		#expect(!restored.config.channelList.contains { $0.uniqueIdentifier == extra.uniqueIdentifier })
	}
}
