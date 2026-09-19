// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// Archive validation is stricter than launch-time migration, which deliberately
/// falls back after malformed fields. No malformed field may silently become a default here.
nonisolated enum SettingsSessionArchive {
	/// A configuration stripped of everything that only means something in this
	/// user account. Whether the connect commands travel is the dictionary's
	/// decision, not this one: see ``portableDictionary(_:includeConnectCommands:)``.
	static func portable(_ config: ServerConfig) -> ServerConfig {
		var config = withoutPendingSecrets(config)
		config.identityClientSideCertificate = nil
		return config
	}

	/** The one place that decides how an export withholds connect commands.

	 They are withheld by removing the key, never by writing an empty list: an
	 omitted list preserves the target's commands, while an included empty list
	 clears them. */
	static func portableDictionary(_ config: ServerConfig,
	                               includeConnectCommands: Bool = false) -> [String: PropertyListValue]
	{
		var dictionary = portable(config).dictionaryValue
		if !includeConnectCommands {
			dictionary.removeValue(forKey: ServerConfig.CodingKeys.loginCommands.rawValue)
		}
		return dictionary
	}

	/** The away nickname's unset state is not meaningful in an archive: a
	 configuration that never had one and one whose field was cleared are the
	 same configuration, so both archive as the empty string and compare
	 equal. */
	static func normalizingAwayNickname(_ config: ServerConfig) -> ServerConfig {
		var config = config
		config.awayNickname = config.awayNickname ?? ""
		return config
	}

	/// Keep local authentication configuration, but never read or archive Keychain contents.
	static func withoutPendingSecrets(_ config: ServerConfig) -> ServerConfig {
		var config = normalizingAwayNickname(config)
		config.pendingNicknamePassword = .unchanged
		config.pendingProxyPassword = .unchanged
		config.serverList = config.serverList.map {
			var server = $0
			server.pendingServerPassword = .unchanged
			return server
		}
		config.conversationList = config.conversationList.map {
			var conversation = $0
			conversation.pendingSecretKey = .unchanged
			return conversation
		}
		return config
	}

	static func decode(_ value: PropertyListValue) throws -> [ServerConfig] {
		guard let array = value.array, array.count <= 1000 else { throw SettingsTransferError.invalidDocument }
		var identifiers: Set<String> = []
		return try array.map { value in
			guard let dictionary = value.dictionary else { throw SettingsTransferError.invalidDocument }
			let validated = try validate(dictionary, kind: .session)
			guard let config = PropertyListModel.decode(ServerConfig.self, from: validated),
			      identifiers.insert(config.uniqueIdentifier).inserted,
			      config.proxyPort > 0,
			      config.floodControlDelayTimerInterval >= ServerConfigDefaults.minimumFloodDelay,
			      config.floodControlDelayTimerInterval <= ServerConfigDefaults.maximumFloodDelay,
			      config.floodControlMaximumMessages >= ServerConfigDefaults.minimumFloodMessages,
			      config.floodControlMaximumMessages <= ServerConfigDefaults.maximumFloodMessages,
			      config.autojoinDelayAfterConnectCommands >= 0,
			      config.autojoinDelayAfterConnectCommands <= ServerConfigDefaults.maximumAutojoinConnectCommandDelay,
			      config.lastMessageServerTime.isFinite,
			      config.highlightList.count == archivedHighlightCount(in: validated),
			      Set(config.conversationList.map(\.name)).count == config.conversationList.count
			else { throw SettingsTransferError.invalidValue(SettingsKeys.Sessions.serverSessions.name) }
			return withoutPendingSecrets(config)
		}
	}

	/// A highlight entry the decoder dropped is a rejected archive, not a
	/// shorter list, so the counts have to match before the value is accepted.
	private static func archivedHighlightCount(in validated: [String: PropertyListValue]) -> Int {
		validated[ServerConfig.CodingKeys.highlightList.rawValue]?.array?.count ?? 0
	}

	private enum Record {
		case session, server, channel, highlight, ignore
	}

	private enum Field {
		case text, flag, unsigned, port, real, bytes, texts
		case records(Record)
	}

	private static func validate(_ dictionary: [String: PropertyListValue],
	                             kind: Record) throws -> [String: PropertyListValue]
	{
		guard let identifier = dictionary["uniqueIdentifier"]?.string, !identifier.isEmpty else {
			throw SettingsTransferError.invalidValue("uniqueIdentifier")
		}
		var result: [String: PropertyListValue] = [:]
		for (name, value) in dictionary {
			guard let field = field(named: name, kind: kind) else { throw SettingsTransferError.invalidValue(name) }
			let coerced: PropertyListValue?
			switch field {
			case .text: coerced = value.string.map(PropertyListValue.string)
			case .flag: coerced = SettingsKey(name, default: false).coerce(value)
			case .unsigned: coerced = SettingsKey(name, default: UInt(0)).coerce(value)
			case .port: coerced = SettingsKey(name, default: UInt16(1), validation: { $0 > 0 }).coerce(value)
			case .real: coerced = SettingsKey(name, default: 0.0).coerce(value)
			case .bytes: coerced = value.data.map(PropertyListValue.data)
			case .texts: coerced = value.stringArray.map(PropertyListValue.init)
			case let .records(record):
				guard let array = value.array else { throw SettingsTransferError.invalidValue(name) }
				var identifiers: Set<String> = []
				coerced = try .array(array.map {
					guard let entry = $0.dictionary,
					      let identifier = entry["uniqueIdentifier"]?.string,
					      identifiers.insert(identifier).inserted
					else { throw SettingsTransferError.invalidValue(name) }
					return try .dictionary(validate(entry, kind: record))
				})
			}
			guard let coerced else { throw SettingsTransferError.invalidValue(name) }
			result[name] = coerced
		}
		try validateDomain(result, kind: kind)
		return result
	}

	private static func validateDomain(_ values: [String: PropertyListValue], kind: Record) throws {
		func unsigned(_ name: String) -> UInt? {
			values[name].flatMap { UInt.settingValue(from: $0.propertyListObject) }
		}
		let valid: Bool = switch kind {
		case .session:
			(unsigned("dictionaryVersion") ?? 0) <= ServerConfigDefaults.dictionaryVersion
				&& unsigned("addressType").map { ConnectionAddressKind(rawValue: $0) != nil } != false
				&& unsigned("proxyType").map { ConnectionProxyKind(rawValue: $0) != nil } != false
				&& unsigned("cipherSuites").map { CipherSuiteCollection(rawValue: $0) != nil } != false
		case .server:
			values["serverAddress"]?.string.map { !$0.isEmpty && !$0.contains(where: \.isWhitespace) } == true
		case .channel:
			values["name"]?.string.map { !$0.isEmpty && !$0.contains(where: \.isWhitespace) } == true
				&& unsigned("type").map { ConversationKind(rawValue: $0) != nil } != false
		case .highlight: values["matchKeyword"]?.string?.isEmpty == false
		case .ignore: unsigned("entryType").map { $0 <= 2 } != false
		}
		guard valid else { throw SettingsTransferError.invalidValue(SettingsKeys.Sessions.serverSessions.name) }
	}

	private static func field(named name: String, kind: Record) -> Field? {
		switch kind {
		case .session: ServerConfig.CodingKeys(rawValue: name).map(sessionField)
		case .server:
			switch name {
			case "uniqueIdentifier", "serverAddress": .text
			case "serverPort": .port
			case "prefersSecuredConnection": .flag
			default: nil
			}
		case .channel:
			channelField(name)
		case .highlight:
			switch name {
			case "uniqueIdentifier", "matchKeyword", "matchChannelId": .text
			case "matchIsExcluded": .flag
			default: nil
			}
		case .ignore:
			switch name {
			case "uniqueIdentifier", "hostmask": .text
			case "entryType": .unsigned
			case "ignoreClientToClientProtocol", "ignoreFileTransferRequests", "ignoreGeneralEventMessages",
			     "ignoreInlineMedia", "ignoreNoticeMessages", "ignorePrivateMessageHighlights", "ignorePrivateMessages",
			     "ignorePublicMessageHighlights", "ignorePublicMessages", "trackUserActivity": .flag
			default: nil
			}
		}
	}

	private static func channelField(_ name: String) -> Field? {
		switch name {
		case "uniqueIdentifier", "name", "label", "defaultModes", "defaultTopic": .text
		case "type": .unsigned
		case "autoJoin", "ignoreGeneralEventMessages", "ignoreHighlights", "inlineMediaDisabled", "inlineMediaEnabled",
		     "pushNotifications", "showsUnreadCount": .flag
		default: nil
		}
	}

	private static func sessionField(_ key: ServerConfig.CodingKeys) -> Field {
		switch key {
		case .uniqueIdentifier, .connectionName, .nickname, .awayNickname, .username, .realName,
		     .saslMechanismPreference,
		     .proxyAddress, .proxyUsername, .normalLeavingComment, .sleepModeLeavingComment, .ctcpVersionReply:
			.text
		case .dictionaryVersion, .addressType, .proxyType, .cipherSuites, .primaryEncoding, .fallbackEncoding,
		     .floodControlDelayTimerInterval, .floodControlMaximumMessages: .unsigned
		case .proxyPort: .port
		case .autojoinDelayAfterConnectCommands, .lastMessageServerTime: .real
		case .identityClientSideCertificate: .bytes
		case .alternateNicknames, .loginCommands: .texts
		case .serverList: .records(.server)
		case .conversationList: .records(.channel)
		case .highlightList: .records(.highlight)
		case .ignoreList: .records(.ignore)
		case .usesSASL, .saslAuthenticationDisableExternalMechanism, .sendAuthenticationRequestsToUserServ,
		     .connectionPrefersIPv4,
		     .validateServerCertificateChain, .autoConnect, .autoReconnect, .autoSleepModeDisconnect,
		     .performDisconnectOnReachabilityChange, .performPongTimer, .performDisconnectOnPongTimer,
		     .disconnectOnSASLFailure,
		     .autojoinWaitsForNickServ, .autojoinWaitsForConnectCommands, .hideAutojoinDelayedWarnings,
		     .hideNetworkUnavailabilityNotices,
		     .sendWhoCommandRequestsToChannels, .setInvisibleModeOnConnect, .runConnectCommandsSilently,
		     .sidebarItemExpanded,
		     .zncIgnoreConfiguredAutojoin, .zncIgnorePlaybackNotifications, .zncIgnoreUserNotifications,
		     .zncOnlyPlaybackLatest: .flag
		}
	}
}
