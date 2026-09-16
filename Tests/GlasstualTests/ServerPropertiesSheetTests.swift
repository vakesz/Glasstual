/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Server properties sheet")
struct ServerPropertiesSheetTests {
	@Test("Closing the sheet suppresses identity enumeration that finishes late", .timeLimit(.minutes(1)))
	func closedCertificateLookupCannotPresent() async throws {
		let sheet = ServerPropertiesSheet(client: nil)
		let (gate, release) = AsyncStream<Void>.makeStream()
		let loading = Task { for await _ in gate {} }
		let (started, didStart) = AsyncStream<Void>.makeStream()
		var presentations = 0
		sheet.certificateSelection.chooseIdentities(using: {
			didStart.yield(())
			await loading.value
			return []
		}, present: { _ in presentations += 1 })
		let pending = try #require(sheet.certificateSelection.task)
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		sheet.sheetDidEnd()
		release.finish()
		await pending.value
		#expect(presentations == 0)
		#expect(sheet.certificateSelection.task == nil)
	}

	@Test("Replacing a certificate choice ignores the earlier reference when it arrives late", .timeLimit(.minutes(1)))
	func newerCertificateSelectionWins() async throws {
		let selection = ClientCertificateSelection()
		let (gate, release) = AsyncStream<Void>.makeStream()
		let loading = Task { for await _ in gate {}; return Data([1]) }
		let (started, didStart) = AsyncStream<Void>.makeStream()
		var applied: [Data] = []
		selection.resolveReference(using: {
			didStart.yield(())
			return await loading.value
		}, apply: { applied.append($0) })
		let old = try #require(selection.task)
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		selection.resolveReference(using: { Data([2]) }, apply: { applied.append($0) })
		await selection.task?.value
		release.finish()
		await old.value
		#expect(applied == [Data([2])])
		#expect(!selection.isResolvingReference)
	}

	@Test("Save includes a chosen certificate whose keychain reference is still loading", .timeLimit(.minutes(1)))
	func saveAwaitsSelectedCertificate() async throws {
		let sheet = ServerPropertiesSheet(client: nil)
		let persistence = KeychainPersistence { _ in }
		sheet.credentialPersistence = persistence
		sheet.model.replace(with: Self.configuration(withSecrets: false))
		let (saved, didSave) = AsyncStream<ClientConfig>.makeStream()
		let delegate = CertificateSaveRecorder(saved: didSave)
		sheet.delegate = delegate
		let (gate, release) = AsyncStream<Void>.makeStream()
		let loading = Task { for await _ in gate {}; return Data([3]) }
		sheet.certificateSelection.resolveReference(using: { await loading.value }, apply: { reference in
			sheet.model.config.identityClientSideCertificate = reference
		})
		sheet.submit()
		#expect(sheet.model.isSaving)
		#expect(delegate.savedCount == 0)
		let quit = persistence.waitForSettingsSaves()
		release.finish()
		var iterator = saved.makeAsyncIterator()
		let submitted = try #require(await iterator.next())
		#expect(submitted.identityClientSideCertificate == Data([3]))
		#expect(delegate.savedCount == 1)
		#expect(!sheet.model.isSaving)
		#expect(await quit.value)
	}

	@Test("The draft validates all persisted fields before submission")
	func draftValidation() throws {
		var config = ClientConfig(connectionName: "Libera")
		config.serverList = [Server(serverAddress: "irc.libera.chat", serverPort: 6697)]
		let model = ServerPropertiesModel(config: config)
		let submitted = try #require(model.submittedConfig())
		#expect(submitted.serverList.first?.serverAddress == "irc.libera.chat")
		model.serverPort = "70000"
		#expect(model.submittedConfig() == nil)
		#expect(model.selection == .general)
		#expect(model.validationMessage == CommonValidationStrings.invalidInternetPort)
	}

	/** A new connection opens on empty fields, which are not a connection — but
	 the sheet used to answer that with a popover the moment it was shown. The
	 message waits for a refused save and then follows the fields, so it goes
	 without another press of Save. */
	@Test("The sheet says nothing until a save is refused, and stops once it is fixed")
	func theMessageWaitsForASaveToBeRefused() {
		let model = ServerPropertiesModel(config: ClientConfig())

		#expect(model.validationFault != nil)
		#expect(model.validationMessage == nil)

		#expect(model.validate() == false)
		#expect(model.validationMessage == CommonValidationStrings.invalidServerAddress)
		#expect(model.selection == .general)

		var config = ClientConfig(connectionName: "Libera")
		config.nickname = "someone"
		config.username = "someone"
		config.realName = "Someone"
		config.serverList = [Server(serverAddress: "irc.libera.chat", serverPort: 6697)]
		model.replace(with: config)

		#expect(model.validationFault == nil)
		#expect(model.validationMessage == nil)
	}

	/** SASL was settable only in the onboarding network picker, so a connection
	 added any other way — the New Server sheet, an imported configuration, a
	 `glasstual://` link — was stuck with whatever the default was. The Identity
	 pane binds it now, and the value survives submission either way. */
	@Test("The Identity pane can turn SASL on and off", arguments: [false, true])
	func saslIsSettableFromTheIdentityPane(_ initialValue: Bool) throws {
		var config = Self.configuration(withSecrets: false)
		config.usesSASL = initialValue
		let model = ServerPropertiesModel(config: config)

		#expect(model.config.usesSASL == initialValue)
		#expect(ServerPropertiesStrings.Identity.signInWithSASL.isEmpty == false)

		model.config.usesSASL = !initialValue
		let submitted = try #require(model.submittedConfig())

		#expect(submitted.usesSASL == !initialValue)
	}

	/// Emptying a secret used to write `nil` into the setter, which the keychain
	/// flush read as "nothing to do": the old password stayed in the keychain and
	/// the field read it straight back the next time the sheet opened.
	@Test("Emptying a secret asks for the keychain item to go")
	func emptiedSecretsAreCleared() throws {
		let model = ServerPropertiesModel(config: Self.configuration(withSecrets: true))
		#expect(model.nicknamePassword == "nick-secret")
		#expect(model.proxyPassword == "proxy-secret")
		#expect(model.serverPassword == "server-secret")

		model.nicknamePassword = ""
		model.proxyPassword = "  "
		model.serverPassword = ""
		let submitted = try #require(model.submittedConfig())

		#expect(submitted.pendingNicknamePassword == .cleared)
		#expect(submitted.pendingProxyPassword == .cleared)
		#expect(submitted.serverList.first?.pendingServerPassword == .cleared)
	}

	@Test("A secret left alone is written back rather than cleared")
	func untouchedSecretsSurviveSubmission() throws {
		let model = ServerPropertiesModel(config: Self.configuration(withSecrets: true))

		let submitted = try #require(model.submittedConfig())

		#expect(submitted.pendingNicknamePassword == .set("nick-secret"))
		#expect(submitted.pendingProxyPassword == .set("proxy-secret"))
		#expect(submitted.serverList.first?.pendingServerPassword == .set("server-secret"))
	}

	/** The sheet reads its three secrets from the keychain a moment after it
	 opens, because `SecItemCopyMatching` is synchronous and the main actor is
	 not the place for three of them. Every untouched field used to submit as
	 `.edited("")` — which is `.cleared` — so pressing OK inside that moment
	 deleted the server, NickServ and proxy passwords. */
	@Test("Saving before the keychain answers asks for no change to any secret")
	func savingBeforeSecretsLoadKeepsThem() throws {
		let config = Self.configuration(withSecrets: false)
		let items = try Self.storedSecrets(for: config)
		defer { Self.deleteSecrets(items) }

		let model = ServerPropertiesModel(config: config)
		/* Nothing has answered yet, so the fields are showing secrets they do
		 not have. */
		#expect(model.serverPassword.isEmpty)
		#expect(model.nicknamePassword.isEmpty)
		#expect(model.proxyPassword.isEmpty)

		let submitted = try #require(model.submittedConfig())

		#expect(submitted.pendingNicknamePassword == .unchanged)
		#expect(submitted.pendingProxyPassword == .unchanged)
		#expect(submitted.serverList.first?.pendingServerPassword == .unchanged)
	}

	@Test("Saving after the keychain answers, with nothing typed, asks for no change")
	func savingAfterSecretsLoadKeepsThem() async throws {
		let config = Self.configuration(withSecrets: false)
		let items = try Self.storedSecrets(for: config)
		defer { Self.deleteSecrets(items) }

		let model = ServerPropertiesModel(config: config)
		await model.loadSecrets()

		#expect(model.nicknamePassword == "stored-nickname")
		#expect(model.proxyPassword == "stored-proxy")
		#expect(model.serverPassword == "stored-server")

		let submitted = try #require(model.submittedConfig())

		#expect(submitted.pendingNicknamePassword == .unchanged)
		#expect(submitted.pendingProxyPassword == .unchanged)
		#expect(submitted.serverList.first?.pendingServerPassword == .unchanged)

		/* Emptying a field the person can now see is still what deletes the
		 secret behind it. */
		model.nicknamePassword = ""
		model.serverPassword = "replacement"

		let edited = try #require(model.submittedConfig())

		#expect(edited.pendingNicknamePassword == .cleared)
		#expect(edited.pendingProxyPassword == .unchanged)
		#expect(edited.serverList.first?.pendingServerPassword == .set("replacement"))
	}

	/// The channel list used to call the keychain once per row every time the
	/// pane was drawn; it answers from the sheet's one read instead, and an
	/// unsaved edit made in the channel sheet wins over what is stored.
	@Test("The channel list marks keys from the sheet's one read and from edits", .timeLimit(.minutes(1)))
	func channelListShowsKeysFromTheLoadedSecrets() async {
		var config = Self.configuration(withSecrets: false)
		let stored = ChannelConfig(channelName: "#stored")
		let bare = ChannelConfig(channelName: "#bare")
		config.channelList = [stored, bare]
		#expect(stored.keychainItem.write("stored-key"))
		defer { stored.keychainItem.delete() }

		let model = ServerPropertiesModel(config: config)

		#expect(model.channelHasSecretKey(stored) == false)

		await model.loadSecrets()

		#expect(model.channelHasSecretKey(stored))
		#expect(model.channelHasSecretKey(bare) == false)

		var cleared = stored
		cleared.pendingSecretKey = .cleared
		var typed = bare
		typed.pendingSecretKey = .set("typed")

		#expect(model.channelHasSecretKey(cleared) == false)
		#expect(model.channelHasSecretKey(typed))
	}

	/// Writes a distinct secret for each of the configuration's three keychain
	/// items, the way a connection the user has already saved carries them.
	private static func storedSecrets(for config: ClientConfig) throws -> [KeychainItem] {
		let server = try #require(config.serverList.first)
		let items: [(KeychainItem, String)] = [
			(config.nicknamePasswordKeychainItem, "stored-nickname"),
			(config.proxyPasswordKeychainItem, "stored-proxy"),
			(server.keychainItem, "stored-server"),
		]

		for (item, password) in items {
			#expect(item.write(password))
		}

		return items.map(\.0)
	}

	private static func deleteSecrets(_ items: [KeychainItem]) {
		for item in items {
			item.delete()
		}
	}

	private static func configuration(withSecrets: Bool) -> ClientConfig {
		var config = ClientConfig(connectionName: "Libera")
		config.nickname = "someone"
		config.username = "someone"
		config.realName = "Someone"
		var server = Server(serverAddress: "irc.libera.chat", serverPort: 6697)
		if withSecrets {
			config.pendingNicknamePassword = .set("nick-secret")
			config.pendingProxyPassword = .set("proxy-secret")
			server.pendingServerPassword = .set("server-secret")
		}
		config.serverList = [server]

		return config
	}

	@Test("Endpoint editing sees pending primary values without submitting unrelated drafts")
	func endpointEditingUsesPendingPrimary() throws {
		let model = ServerPropertiesModel(config: Self.configuration(withSecrets: true))
		model.serverAddress = "pending.example.test"
		model.serverPort = "7000"
		model.serverPassword = "new-server-secret"
		model.nicknamePassword = ""
		model.proxyPort = "not yet valid"
		let servers = try #require(model.serverListForEditing())
		let child = ServerEndpointListModel()
		child.replace(with: servers)
		let primary = try #require(child.entries.first)
		#expect(primary.address == "pending.example.test")
		#expect(primary.port == "7000")
		#expect(primary.password == "new-server-secret")
		#expect(model.config.serverList.first?.serverAddress == "irc.libera.chat")
		#expect(model.proxyPort == "not yet valid")
	}

	@Test("Saving alternate servers preserves unrelated parent drafts and secret clear intent")
	func endpointSavePreservesParentDrafts() throws {
		let model = ServerPropertiesModel(config: Self.configuration(withSecrets: true))
		model.nicknamePassword = ""
		model.proxyPassword = "replacement-proxy-secret"
		model.proxyAddress = "pending-proxy.example.test"
		model.proxyPort = "1234"
		model.proxyUsername = "pending-user"
		model.alternateNicknames = "second third"
		model.connectCommands = "/mode +i\n/join #pending"
		model.serverPassword = ""
		let child = ServerEndpointListModel()
		try child.replace(with: #require(model.serverListForEditing()))
		#expect(child.entries.first?.password == "")
		child.entries[0].address = "edited.example.test"
		child.entries[0].port = "6699"
		child.entries[0].prefersSecuredConnection = true
		child.addEntry()
		child.entries[1].address = "alternate.example.test"
		child.entries[1].password = "alternate-secret"
		try model.applyServerList(#require(child.validatedServers()))

		#expect(model.serverAddress == "edited.example.test")
		#expect(model.serverPort == "6699")
		#expect(model.primaryServerIsSecured)
		#expect(model.nicknamePassword == "")
		#expect(model.proxyPassword == "replacement-proxy-secret")
		#expect(model.proxyAddress == "pending-proxy.example.test")
		#expect(model.proxyPort == "1234")
		#expect(model.proxyUsername == "pending-user")
		#expect(model.alternateNicknames == "second third")
		#expect(model.connectCommands == "/mode +i\n/join #pending")
		let submitted = try #require(model.submittedConfig())
		#expect(submitted.pendingNicknamePassword == .cleared)
		#expect(submitted.pendingProxyPassword == .set("replacement-proxy-secret"))
		#expect(submitted.serverList.first?.pendingServerPassword == .cleared)
		#expect(submitted.serverList.last?.pendingServerPassword == .set("alternate-secret"))
	}

	@Test("Endpoint handoff rejects an invalid primary port without replacing it with a saved port")
	func endpointHandoffDoesNotLoseInvalidPort() {
		let model = ServerPropertiesModel(config: Self.configuration(withSecrets: true))
		model.serverPort = "70000"
		#expect(model.serverListForEditing() == nil)
		#expect(model.serverPort == "70000")
		#expect(model.validationMessage == CommonValidationStrings.invalidInternetPort)
	}

	@Test("Promoting an alternate endpoint keeps each endpoint's own secret intent")
	func promotedEndpointKeepsItsSecret() throws {
		var config = Self.configuration(withSecrets: true)
		config.serverList.append(Server(serverAddress: "alternate.example.test", serverPort: 6697,
		                                pendingServerPassword: .set("alternate-secret")))
		let model = ServerPropertiesModel(config: config)
		model.serverPassword = ""
		var servers = try #require(model.serverListForEditing())
		servers.swapAt(0, 1)
		model.applyServerList(servers)
		#expect(model.serverPassword == "alternate-secret")
		let submitted = try #require(model.submittedConfig())
		#expect(submitted.serverList[0].pendingServerPassword == .set("alternate-secret"))
		#expect(submitted.serverList[1].pendingServerPassword == .cleared)
	}

	@Test("Identity fields accept what IRC accepts and nothing else")
	func identityValidationMatchesIRCRestrictions() {
		#expect(ServerPropertiesValidation.isNickname("valid_nick"))
		#expect(ServerPropertiesValidation.isNickname("invalid nickname") == false)
		#expect(ServerPropertiesValidation.isUsername("valid-user"))
		#expect(ServerPropertiesValidation.isUsername("invalid user") == false)
		#expect(ServerPropertiesValidation.invalidAlternateNickname(in: "") == nil)
		#expect(ServerPropertiesValidation.invalidAlternateNickname(in: "   ") == nil)
		#expect(ServerPropertiesValidation.invalidAlternateNickname(in: "first second") == nil)
		// The message names the one that failed, so the check reports it.
		#expect(ServerPropertiesValidation.invalidAlternateNickname(in: "first invalid!nick") == "invalid!nick")
	}

	@Test("An endpoint needs a host that resolves as a name or an address, and a port in range")
	func endpointValidationRejectsInvalidAddressesAndPorts() {
		#expect(ServerPropertiesValidation.isInternetAddress("irc.libera.chat"))
		#expect(ServerPropertiesValidation.isInternetAddress("2001:db8::1"))
		#expect(ServerPropertiesValidation.isInternetAddress("not a host") == false)
		#expect(ServerPropertiesValidation.isInternetPort("6697"))
		#expect(ServerPropertiesValidation.isInternetPort("0") == false)
		#expect(ServerPropertiesValidation.isInternetPort("70000") == false)
	}

	@Test("A disconnect message stays inside the protocol's length limit and on one line")
	func disconnectMessageValidationPreservesProtocolLimit() {
		#expect(ServerPropertiesValidation.isLeavingComment(String(repeating: "a", count: 390)))
		#expect(ServerPropertiesValidation.isLeavingComment(String(repeating: "a", count: 391)) == false)
		#expect(ServerPropertiesValidation.isLeavingComment("first\nsecond") == false)
		/* 130 three-byte characters are 390 bytes, and one more is over the
		 limit however few characters it looks like. */
		#expect(ServerPropertiesValidation.isLeavingComment(String(repeating: "€", count: 130)))
		#expect(ServerPropertiesValidation.isLeavingComment(String(repeating: "€", count: 131)) == false)
	}
}

@MainActor
private final class CertificateSaveRecorder: ServerPropertiesSheetDelegate {
	let saved: AsyncStream<ClientConfig>.Continuation
	private(set) var savedCount = 0

	init(saved: AsyncStream<ClientConfig>.Continuation) {
		self.saved = saved
	}

	func serverPropertiesSheet(_: ServerPropertiesSheet, onOk config: ClientConfig) {
		savedCount += 1
		saved.yield(config)
		saved.finish()
	}
}
