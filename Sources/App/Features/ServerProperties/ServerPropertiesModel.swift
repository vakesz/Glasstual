/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit
import Observation

@MainActor
@Observable
final class ServerPropertiesModel {
	var config: ClientConfig
	var selection: ServerPropertiesSelection = .general
	var validationMessage: String?
	var isValidationMessagePresented = false
	var selectedAddressBookEntryID: String?
	var selectedChannelID: String?
	var selectedHighlightID: String?

	var serverAddress: String
	var serverPort: String
	var proxyAddress: String
	var proxyPort: String
	var proxyUsername: String
	var alternateNicknames: String
	var connectCommands: String

	/** The three keychain-backed fields.

	 Each one starts empty, holds whatever the one keychain read finds, and is
	 only written back to the keychain when the person typed into it. The
	 distinction matters because the read lands after the sheet is on screen:
	 a field seeded from the pending edit alone reads empty until then, and
	 submitting an empty field as an edit is what deletes the stored secret. */
	var serverPassword: String {
		get { serverPasswordText }
		set {
			guard newValue != serverPasswordText else { return }
			serverPasswordText = newValue
			editedSecretFields.insert(.serverPassword)
		}
	}

	var nicknamePassword: String {
		get { nicknamePasswordText }
		set {
			guard newValue != nicknamePasswordText else { return }
			nicknamePasswordText = newValue
			editedSecretFields.insert(.nicknamePassword)
		}
	}

	var proxyPassword: String {
		get { proxyPasswordText }
		set {
			guard newValue != proxyPasswordText else { return }
			proxyPasswordText = newValue
			editedSecretFields.insert(.proxyPassword)
		}
	}

	private var serverPasswordText: String
	private var nicknamePasswordText: String
	private var proxyPasswordText: String

	/// Which of the three fields the person has typed into. A field that is not
	/// in here keeps whatever edit the configuration already carried, so a sheet
	/// dismissed with OK before — or without — the keychain read leaves every
	/// stored secret alone.
	private var editedSecretFields: Set<SecretField> = []

	private enum SecretField {
		case serverPassword
		case nicknamePassword
		case proxyPassword
	}

	/// What the one keychain read found, by item. Empty until it answers.
	private var loadedSecrets: [KeychainItem: String] = [:]
	@ObservationIgnored private var secretsTask: Task<Void, Never>?

	var certificateName = ServerPropertiesStrings.Certificate.noneSelected
	var certificateSHA512 = ServerPropertiesStrings.Certificate.noneSelected
	var certificateSHA256 = ServerPropertiesStrings.Certificate.noneSelected
	var certificateSHA1 = ServerPropertiesStrings.Certificate.noneSelected

	init(config: ClientConfig) {
		self.config = config
		let primary = config.serverList.first
		serverAddress = primary?.serverAddress ?? ""
		serverPort = String(primary?.serverPort ?? UInt16(IRCConnectionDefaults.serverPort))
		/* Only the unflushed edits, because reading the stored ones means three
		 synchronous keychain lookups. `loadSecrets()` fills the rest in, and
		 until it does an untouched field submits as `.unchanged` rather than as
		 an emptied one. */
		serverPasswordText = primary?.pendingServerPassword.value(orStored: nil) ?? ""
		nicknamePasswordText = config.pendingNicknamePassword.value(orStored: nil) ?? ""
		proxyAddress = config.proxyAddress ?? ""
		proxyPort = String(config.proxyPort)
		proxyUsername = config.proxyUsername ?? ""
		proxyPasswordText = config.pendingProxyPassword.value(orStored: nil) ?? ""
		alternateNicknames = config.alternateNicknames.joined(separator: " ")
		connectCommands = config.loginCommands.joined(separator: "\n")
	}

	var displayedChannels: [ChannelConfig] {
		config.channelList.filter { $0.type == .channel }
	}

	func replace(with config: ClientConfig) {
		self.config = config
		let replacement = ServerPropertiesModel(config: config)
		serverAddress = replacement.serverAddress
		serverPort = replacement.serverPort
		proxyAddress = replacement.proxyAddress
		proxyPort = replacement.proxyPort
		proxyUsername = replacement.proxyUsername
		alternateNicknames = replacement.alternateNicknames
		connectCommands = replacement.connectCommands
		/* The secrets come from the one read this sheet already did. Rebuilding
		 them from the config meant three more keychain lookups on the main
		 actor every time anything else on the sheet changed. The replacement is
		 a fresh configuration, so nothing in it has been typed into yet. */
		editedSecretFields = []
		serverPasswordText = secret(
			primaryServer?.pendingServerPassword ?? .unchanged,
			from: primaryServer?.keychainItem
		)
		nicknamePasswordText = secret(config.pendingNicknamePassword, from: config.nicknamePasswordKeychainItem)
		proxyPasswordText = secret(config.pendingProxyPassword, from: config.proxyPasswordKeychainItem)
	}

	/** Reads the sheet's secrets once, off the main actor.

	 `SecItemCopyMatching` is synchronous and answers at the keychain's pace;
	 one call per secret ran on the main actor for every sheet, and again for
	 every `replace(with:)`. The answers are cached for as long as the sheet
	 lives. */
	func loadSecrets() {
		guard secretsTask == nil else { return }

		let items = secretKeychainItems
		secretsTask = Task { [weak self] in
			let passwords = await KeychainSecretLoader.passwords(for: items)
			self?.applyLoadedSecrets(passwords)
		}
	}

	isolated deinit {
		secretsTask?.cancel()
	}

	private var secretKeychainItems: [KeychainItem] {
		var items = [config.nicknamePasswordKeychainItem, config.proxyPasswordKeychainItem]

		if let primaryServer {
			items.append(primaryServer.keychainItem)
		}

		return items
	}

	private func applyLoadedSecrets(_ passwords: [KeychainItem: String]) {
		guard Task.isCancelled == false else { return }
		loadedSecrets = passwords

		/* A field the user has already typed into keeps what they typed — an
		 emptied one included, which is why this asks what was edited rather
		 than what is empty. */
		if editedSecretFields.contains(.serverPassword) == false {
			serverPasswordText = secret(
				primaryServer?.pendingServerPassword ?? .unchanged,
				from: primaryServer?.keychainItem
			)
		}
		if editedSecretFields.contains(.nicknamePassword) == false {
			nicknamePasswordText = secret(config.pendingNicknamePassword, from: config.nicknamePasswordKeychainItem)
		}
		if editedSecretFields.contains(.proxyPassword) == false {
			proxyPasswordText = secret(config.pendingProxyPassword, from: config.proxyPasswordKeychainItem)
		}
	}

	/// An unflushed edit if there is one, and otherwise what the one keychain
	/// read found. Never a keychain read of its own.
	private func secret(_ pending: PendingKeychainSecret, from item: KeychainItem?) -> String {
		pending.value(orStored: item.flatMap { loadedSecrets[$0] }) ?? ""
	}

	/** What submitting one of the three fields asks the keychain to do.

	 Only a field the person typed into carries an instruction; every other one
	 hands back the edit the configuration already had, which is normally
	 `.unchanged`. Emitting `.edited(text)` for an untouched field wrote
	 `.cleared` for as long as the keychain read had not landed, which deleted
	 the secret the sheet had not finished showing. */
	private func submittedSecret(
		_ field: SecretField,
		text: String,
		pending: PendingKeychainSecret
	) -> PendingKeychainSecret {
		editedSecretFields.contains(field) ? .edited(text.trimmed) : pending
	}

	func serverListForEditing() -> [Server]? {
		let error: String? = if !ServerPropertiesValidation.isInternetAddress(serverAddress.firstToken) {
			CommonValidationStrings.invalidServerAddress
		} else if !ServerPropertiesValidation.isInternetPort(serverPort) {
			CommonValidationStrings.invalidInternetPort
		} else {
			nil
		}
		if let error {
			selection = .general
			validationMessage = error
			isValidationMessagePresented = true
			return nil
		}
		var servers = config.serverList
		var primary = primaryServer ?? Server()
		primary.serverAddress = serverAddress.firstToken.lowercased()
		primary.serverPort = UInt16(serverPort) ?? primary.serverPort
		primary.pendingServerPassword = submittedSecret(
			.serverPassword,
			text: serverPassword,
			pending: primary.pendingServerPassword
		)
		if servers.isEmpty {
			servers.append(primary)
		} else {
			servers[0] = primary
		}
		return servers
	}

	func applyServerList(_ servers: [Server]) {
		config.serverList = servers
		let primary = servers.first
		serverAddress = primary?.serverAddress ?? ""
		serverPort = String(primary?.serverPort ?? UInt16(IRCConnectionDefaults.serverPort))
		/* The endpoint sheet answers with the edits it collected, so the primary
		 endpoint's secret is whatever came back from it, resolved against the
		 read this sheet already did. Asking `Server.serverPassword` was a
		 synchronous keychain lookup on the main actor for a value that is
		 already here. */
		editedSecretFields.remove(.serverPassword)
		serverPasswordText = secret(primary?.pendingServerPassword ?? .unchanged, from: primary?.keychainItem)
	}

	/// Turns TLS on or off for the primary endpoint, moving the port with it the
	/// way the endpoint-list sheet does.
	func setPrimaryServerSecured(_ secured: Bool) {
		var server = primaryServer ?? Server()
		server.serverPort = UInt16(serverPort) ?? server.serverPort
		server = ServerEndpointValidation.server(server, preferringSecuredConnection: secured)
		serverPort = String(server.serverPort)
		storePrimaryServer(server)
	}

	var primaryServerIsSecured: Bool {
		get { primaryServer?.prefersSecuredConnection ?? false }
		set { setPrimaryServerSecured(newValue) }
	}

	func submittedConfig() -> ClientConfig? {
		guard validate() else { return nil }
		var result = config
		var server = primaryServer ?? Server()
		server.serverAddress = serverAddress.firstToken.lowercased()
		server.serverPort = UInt16(serverPort) ?? UInt16(IRCConnectionDefaults.serverPort)
		server.pendingServerPassword = submittedSecret(
			.serverPassword,
			text: serverPassword,
			pending: server.pendingServerPassword
		)
		if result.serverList.isEmpty {
			result.serverList = [server]
		} else {
			result.serverList[0] = server
		}
		result.nickname = result.nickname.firstToken
		result.awayNickname = Self.nilIfEmpty(result.awayNickname?.firstToken ?? "")
		result.username = result.username.firstToken
		result.ctcpVersionReply = Self.nilIfEmpty(result.ctcpVersionReply?.trimmed ?? "")
		result.pendingNicknamePassword = submittedSecret(
			.nicknamePassword,
			text: nicknamePassword,
			pending: result.pendingNicknamePassword
		)
		result.alternateNicknames = uniqueNonempty(alternateNicknames.components(separatedBy: .whitespaces))
		result.proxyAddress = Self.nilIfEmpty(proxyAddress.firstToken.lowercased())
		result.proxyPort = UInt16(proxyPort) ?? UInt16(IRCConnectionDefaults.proxyPort)
		result.proxyUsername = Self.nilIfEmpty(proxyUsername.firstToken)
		result.pendingProxyPassword = submittedSecret(
			.proxyPassword,
			text: proxyPassword,
			pending: result.pendingProxyPassword
		)
		result.loginCommands = connectCommands.components(separatedBy: .newlines)
			.map(\.trimmed).filter { !$0.isEmpty }
		return result
	}

	@discardableResult
	func validate() -> Bool {
		let error: (ServerPropertiesSelection, String)? = if config.connectionName.trimmed
			.isEmpty || !ServerPropertiesValidation.isSingleLine(config.connectionName)
		{
			(.general, CommonValidationStrings.singleLineRequired)
		} else if !ServerPropertiesValidation.isInternetAddress(serverAddress.firstToken) {
			(.general, CommonValidationStrings.invalidServerAddress)
		} else if !ServerPropertiesValidation.isInternetPort(serverPort) {
			(.general, CommonValidationStrings.invalidInternetPort)
		} else if !ServerPropertiesValidation.isNickname(config.nickname.firstToken) {
			(.identity, CommonValidationStrings.invalidNickname)
		} else if let away = config.awayNickname, !away.isEmpty,
		          !ServerPropertiesValidation.isNickname(away.firstToken)
		{
			(.identity, CommonValidationStrings.invalidNickname)
		} else if let nickname = ServerPropertiesValidation.invalidAlternateNickname(in: alternateNicknames) {
			(.identity, ServerPropertiesStrings.Validation.invalidAlternateNickname(nickname))
		} else if !ServerPropertiesValidation.isUsername(config.username.firstToken) {
			(.identity, ServerPropertiesStrings.Validation.invalidUsername)
		} else if config.realName.trimmed.isEmpty || !ServerPropertiesValidation.isSingleLine(config.realName) {
			(.identity, ServerPropertiesStrings.Validation.invalidRealName)
		} else if !ServerPropertiesValidation.isLeavingComment(config.normalLeavingComment) ||
			!ServerPropertiesValidation.isLeavingComment(config.sleepModeLeavingComment)
		{
			(.disconnectMessages, CommonValidationStrings.maximumLength(
				ServerPropertiesValidation.maximumCommentLength
			))
		} else if Self.proxyTypeUsesAddress(config.proxyType),
		          !ServerPropertiesValidation.isInternetAddress(proxyAddress.firstToken)
		{
			(.proxyServer, ServerPropertiesStrings.Validation.invalidProxyAddress)
		} else if Self.proxyTypeUsesAddress(config.proxyType), !ServerPropertiesValidation.isInternetPort(proxyPort) {
			(.proxyServer, CommonValidationStrings.invalidInternetPort)
		} else {
			nil
		}

		guard let error else {
			validationMessage = nil
			isValidationMessagePresented = false
			return true
		}
		selection = error.0
		validationMessage = error.1
		isValidationMessagePresented = true
		return false
	}

	static func nilIfEmpty(_ value: String) -> String? {
		value.isEmpty ? nil : value
	}

	static func proxyType(forTag tag: Int) -> IRCConnectionProxyType {
		guard tag >= 0, let type = IRCConnectionProxyType(rawValue: UInt(tag)) else { return .none }
		return type
	}

	static func proxyTypeUsesAddress(_ type: IRCConnectionProxyType) -> Bool {
		[.socks5, .HTTP].contains(type)
	}

	static func encoding(forTag tag: Int, default fallback: String.Encoding) -> UInt {
		tag > 0 ? UInt(tag) : fallback.rawValue
	}

	private var primaryServer: Server? {
		config.serverList.first
	}

	private func storePrimaryServer(_ server: Server) {
		if config.serverList.isEmpty {
			config.serverList.append(server)
		} else {
			config.serverList[0] = server
		}
	}

	private func uniqueNonempty(_ values: [String]) -> [String] {
		var seen = Set<String>()
		return values.filter { !$0.isEmpty && seen.insert($0).inserted }
	}
}

private extension String {
	var trimmed: String {
		trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

/** Reads keychain secrets away from the main actor.

 Every `KeychainItem.password` is a synchronous `SecItemCopyMatching`, and a
 sheet needs several at once: read them together, off the main actor, and let
 the sheet cache the answers for as long as it is open. */
nonisolated enum KeychainSecretLoader { // nonisolated: value
	@concurrent
	static func passwords(for items: [KeychainItem]) async -> [KeychainItem: String] {
		var passwords: [KeychainItem: String] = [:]

		for item in Set(items) {
			if let password = item.password {
				passwords[item] = password
			}
		}

		return passwords
	}
}
