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
	var serverPassword: String
	var nicknamePassword: String
	var proxyAddress: String
	var proxyPort: String
	var proxyUsername: String
	var proxyPassword: String
	var alternateNicknames: String
	var connectCommands: String

	var certificateName = ServerPropertiesStrings.Certificate.noneSelected
	var certificateSHA512 = ServerPropertiesStrings.Certificate.noneSelected
	var certificateSHA256 = ServerPropertiesStrings.Certificate.noneSelected
	var certificateSHA1 = ServerPropertiesStrings.Certificate.noneSelected

	init(config: ClientConfig) {
		self.config = config
		let primary = config.serverList.first
		serverAddress = primary?.serverAddress ?? ""
		serverPort = String(primary?.serverPort ?? UInt16(IRCConnectionDefaults.serverPort))
		serverPassword = primary?.serverPassword ?? ""
		nicknamePassword = config.nicknamePassword ?? ""
		proxyAddress = config.proxyAddress ?? ""
		proxyPort = String(config.proxyPort)
		proxyUsername = config.proxyUsername ?? ""
		proxyPassword = config.proxyPassword ?? ""
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
		serverPassword = replacement.serverPassword
		nicknamePassword = replacement.nicknamePassword
		proxyAddress = replacement.proxyAddress
		proxyPort = replacement.proxyPort
		proxyUsername = replacement.proxyUsername
		proxyPassword = replacement.proxyPassword
		alternateNicknames = replacement.alternateNicknames
		connectCommands = replacement.connectCommands
	}

	func securedConnectionChanged() {
		guard var server = primaryServer else { return }
		if server.prefersSecuredConnection, serverPort == "6667" {
			serverPort = "6697"
		} else if !server.prefersSecuredConnection, serverPort == "6697" {
			serverPort = "6667"
		}
		server.serverPort = UInt16(serverPort) ?? server.serverPort
		storePrimaryServer(server)
	}

	func setPrimaryServerSecured(_ secured: Bool) {
		var server = primaryServer ?? Server()
		server.prefersSecuredConnection = secured
		storePrimaryServer(server)
		securedConnectionChanged()
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
		server.serverPassword = Self.nilIfEmpty(serverPassword.trimmed)
		if result.serverList.isEmpty {
			result.serverList = [server]
		} else {
			result.serverList[0] = server
		}
		result.nickname = result.nickname.firstToken
		result.awayNickname = Self.nilIfEmpty(result.awayNickname?.firstToken ?? "")
		result.username = result.username.firstToken
		result.ctcpVersionReply = Self.nilIfEmpty(result.ctcpVersionReply?.trimmed ?? "")
		result.nicknamePassword = Self.nilIfEmpty(nicknamePassword.trimmed)
		result.alternateNicknames = uniqueNonempty(alternateNicknames.components(separatedBy: .whitespaces))
		result.proxyAddress = Self.nilIfEmpty(proxyAddress.firstToken.lowercased())
		result.proxyPort = UInt16(proxyPort) ?? UInt16(IRCConnectionDefaults.proxyPort)
		result.proxyUsername = Self.nilIfEmpty(proxyUsername.firstToken)
		result.proxyPassword = Self.nilIfEmpty(proxyPassword.trimmed)
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
