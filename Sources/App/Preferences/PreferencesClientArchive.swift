/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit

/// Archive validation is stricter than launch-time migration, which deliberately
/// falls back after malformed fields. No malformed field may silently become a default here.
nonisolated enum PreferencesClientArchive { // nonisolated: value
	/// A configuration stripped of everything that only means something in this
	/// user account. Whether the connect commands travel is the dictionary's
	/// decision, not this one: see ``portableDictionary(_:includeConnectCommands:)``.
	static func portable(_ config: ClientConfig) -> ClientConfig {
		var config = withoutPendingSecrets(config)
		config.identityClientSideCertificate = nil
		return config
	}

	/** The one place that decides how an export withholds connect commands.

	 They are withheld by removing the key, never by writing an empty list: an
	 omitted list preserves the target's commands, while an included empty list
	 clears them. */
	static func portableDictionary(_ config: ClientConfig,
	                               includeConnectCommands: Bool = false) -> [String: PropertyListValue]
	{
		var dictionary = portable(config).dictionaryValue
		if !includeConnectCommands {
			dictionary.removeValue(forKey: ClientConfig.CodingKeys.loginCommands.rawValue)
		}
		return dictionary
	}

	/** The away nickname's unset state is not meaningful in an archive: a
	 configuration that never had one and one whose field was cleared are the
	 same configuration, so both archive as the empty string and compare
	 equal. */
	static func normalizingAwayNickname(_ config: ClientConfig) -> ClientConfig {
		var config = config
		config.awayNickname = config.awayNickname ?? ""
		return config
	}

	/// Keep local authentication configuration, but never read or archive Keychain contents.
	static func withoutPendingSecrets(_ config: ClientConfig) -> ClientConfig {
		var config = normalizingAwayNickname(config)
		config.pendingNicknamePassword = .unchanged
		config.pendingProxyPassword = .unchanged
		config.serverList = config.serverList.map {
			var server = $0
			server.pendingServerPassword = .unchanged
			return server
		}
		config.channelList = config.channelList.map {
			var channel = $0
			channel.pendingSecretKey = nil
			return channel
		}
		return config
	}

	static func decode(_ value: PropertyListValue) throws -> [ClientConfig] {
		guard let array = value.array, array.count <= 1000 else { throw PreferencesTransferError.invalidDocument }
		var identifiers: Set<String> = []
		return try array.map { value in
			guard let dictionary = value.dictionary else { throw PreferencesTransferError.invalidDocument }
			let validated = try validate(dictionary, kind: .client)
			guard let config = PropertyListModel.decode(ClientConfig.self, from: validated),
			      identifiers.insert(config.uniqueIdentifier).inserted,
			      config.proxyPort > 0,
			      config.floodControlDelayTimerInterval >= ClientConfigDefaults.minimumFloodDelay,
			      config.floodControlDelayTimerInterval <= ClientConfigDefaults.maximumFloodDelay,
			      config.floodControlMaximumMessages >= ClientConfigDefaults.minimumFloodMessages,
			      config.floodControlMaximumMessages <= ClientConfigDefaults.maximumFloodMessages,
			      config.autojoinDelayAfterConnectCommands >= 0,
			      config.autojoinDelayAfterConnectCommands <= ClientConfigDefaults.maximumAutojoinConnectCommandDelay,
			      config.lastMessageServerTime.isFinite,
			      config.highlightList.count == archivedHighlightCount(in: validated),
			      Set(config.channelList.map(\.channelName)).count == config.channelList.count
			else { throw PreferencesTransferError.invalidValue(Preferences.Connection.clientList.name) }
			return withoutPendingSecrets(config)
		}
	}

	/// A highlight entry the decoder dropped is a rejected archive, not a
	/// shorter list, so the counts have to match before the value is accepted.
	private static func archivedHighlightCount(in validated: [String: PropertyListValue]) -> Int {
		validated[ClientConfig.CodingKeys.highlightList.rawValue]?.array?.count ?? 0
	}

	private enum Record {
		case client, server, channel, highlight, ignore, flood
	}

	private enum Field {
		case text, flag, unsigned, port, real, bytes, texts, notifications
		case records(Record)
		case record(Record)
	}

	private static func validate(_ dictionary: [String: PropertyListValue],
	                             kind: Record) throws -> [String: PropertyListValue]
	{
		if kind != .flood {
			guard let identifier = dictionary["uniqueIdentifier"]?.string, !identifier.isEmpty else {
				throw PreferencesTransferError.invalidValue("uniqueIdentifier")
			}
		}
		var result: [String: PropertyListValue] = [:]
		for (name, value) in dictionary {
			guard let field = field(named: name, kind: kind) else { throw PreferencesTransferError.invalidValue(name) }
			let coerced: PropertyListValue?
			switch field {
			case .text: coerced = value.string.map(PropertyListValue.string)
			case .flag: coerced = PreferenceKey(name, default: false).coerce(value)
			case .unsigned: coerced = PreferenceKey(name, default: UInt(0)).coerce(value)
			case .port: coerced = PreferenceKey(name, default: UInt16(1), validation: { $0 > 0 }).coerce(value)
			case .real: coerced = PreferenceKey(name, default: 0.0).coerce(value)
			case .bytes: coerced = value.data.map(PropertyListValue.data)
			case .texts: coerced = value.stringArray.map(PropertyListValue.init)
			case .notifications:
				try validateNotifications(value, name: name)
				coerced = value
			case let .records(record):
				guard let array = value.array else { throw PreferencesTransferError.invalidValue(name) }
				var identifiers: Set<String> = []
				coerced = try .array(array.map {
					guard let entry = $0.dictionary,
					      let identifier = entry["uniqueIdentifier"]?.string,
					      identifiers.insert(identifier).inserted
					else { throw PreferencesTransferError.invalidValue(name) }
					return try .dictionary(validate(entry, kind: record))
				})
			case let .record(record):
				guard let entry = value.dictionary else { throw PreferencesTransferError.invalidValue(name) }
				coerced = try .dictionary(validate(entry, kind: record))
			}
			guard let coerced else { throw PreferencesTransferError.invalidValue(name) }
			result[name] = coerced
		}
		try validateDomain(result, kind: kind)
		return result
	}

	private static func validateNotifications(_ value: PropertyListValue, name: String) throws {
		guard let notifications = value.dictionary else { throw PreferencesTransferError.invalidValue(name) }
		for setting in notifications.values {
			switch setting {
			case .string, .boolean: break
			default: throw PreferencesTransferError.invalidValue(name)
			}
		}
	}

	private static func validateDomain(_ values: [String: PropertyListValue], kind: Record) throws {
		func unsigned(_ name: String) -> UInt? {
			values[name].flatMap { UInt.preferenceValue(from: $0.propertyListObject) }
		}
		let valid: Bool = switch kind {
		case .client:
			(unsigned("dictionaryVersion") ?? 0) <= ClientConfigDefaults.dictionaryVersion
				&& unsigned("addressType").map { IRCConnectionAddressType(rawValue: $0) != nil } != false
				&& unsigned("proxyType").map { IRCConnectionProxyType(rawValue: $0) != nil } != false
				&& unsigned("cipherSuites").map { CipherSuiteCollection(rawValue: $0) != nil } != false
		case .server:
			values["serverAddress"]?.string.map { !$0.isEmpty && !$0.contains(where: \.isWhitespace) } == true
		case .channel:
			values["channelName"]?.string.map { !$0.isEmpty && !$0.contains(where: \.isWhitespace) } == true
				&& unsigned("channelType").map { ChannelType(rawValue: $0) != nil } != false
		case .highlight: values["matchKeyword"]?.string?.isEmpty == false
		case .ignore: unsigned("entryType").map { $0 <= 2 } != false
		case .flood: true
		}
		guard valid else { throw PreferencesTransferError.invalidValue(Preferences.Connection.clientList.name) }
	}

	private static func field(named name: String, kind: Record) -> Field? {
		switch kind {
		case .client: ClientConfig.CodingKeys(rawValue: name).map(clientField)
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
			case "uniqueIdentifier", "matchKeyword", "matchChannelID": .text
			case "matchIsExcluded": .flag
			default: nil
			}
		case .ignore:
			switch name {
			case "uniqueIdentifier", "hostmask": .text
			case "entryType": .unsigned
			case "ignoreClientToClientProtocol", "ignoreFileTransferRequests", "ignoreGeneralEventMessages",
			     "ignoreInlineMedia", "ignoreNoticeMessages", "ignorePrivateMessageHighlights", "ignorePrivateMessages",
			     "ignorePublicMessageHighlights", "ignorePublicMessages", "trackUserActivity", "ignoreCTCP",
			     "ignoreJPQE",
			     "ignoreNotices", "ignorePMHighlights", "ignorePrivateMsg", "ignoreHighlights", "ignorePublicMsg",
			     "notifyJoins": .flag
			default: nil
			}
		case .flood:
			switch name {
			case "serviceEnabled": .flag
			case "delayTimerInterval", "maximumMessageCount": .unsigned
			default: nil
			}
		}
	}

	private static func channelField(_ name: String) -> Field? {
		switch name {
		case "uniqueIdentifier", "channelName", "label", "defaultMode", "defaultTopic": .text
		case "channelType": .unsigned
		case "notifications": .notifications
		case "autoJoin", "ignoreGeneralEventMessages", "ignoreHighlights", "inlineMediaDisabled", "inlineMediaEnabled",
		     "pushNotifications", "showTreeBadgeCount", "joinOnConnect", "ignoreJPQActivity", "enableNotifications",
		     "enableTreeBadgeCountDrawing", "ignoreInlineMedia": .flag
		default: nil
		}
	}

	private static func clientField(_ key: ClientConfig.CodingKeys) -> Field {
		switch key {
		case .uniqueIdentifier, .connectionName, .nickname, .awayNickname, .username, .realName,
		     .saslMechanismPreference,
		     .proxyAddress, .proxyUsername, .normalLeavingComment, .sleepModeLeavingComment, .ctcpVersionReply,
		     .serverAddress, .identityAwayNickname, .identityNickname, .connectionDisconnectDefaultMessage,
		     .proxyServerAddress, .proxyServerUsername, .identityRealname, .connectionDisconnectSleepModeMessage,
		     .identityUsername:
			.text
		case .dictionaryVersion, .addressType, .proxyType, .cipherSuites, .primaryEncoding, .fallbackEncoding,
		     .floodControlDelayTimerInterval, .floodControlMaximumMessages, .proxyServerType,
		     .characterEncodingDefault, .characterEncodingFallback: .unsigned
		case .proxyPort, .serverPort, .proxyServerPort: .port
		case .autojoinDelayAfterConnectCommands, .lastMessageServerTime,
		     .cachedLastServerTimeCapacityReceivedAtTimestamp: .real
		case .identityClientSideCertificate, .identitySSLCertificate: .bytes
		case .alternateNicknames, .loginCommands, .identityAlternateNicknames: .texts
		case .serverList: .records(.server)
		case .channelList: .records(.channel)
		case .highlightList: .records(.highlight)
		case .ignoreList: .records(.ignore)
		case .floodControl: .record(.flood)
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
		     .zncOnlyPlaybackLatest,
		     .prefersSecuredConnection, .connectionPrefersModernCiphers, .connectOnLaunch, .connectOnDisconnect,
		     .disconnectOnSleepMode,
		     .autojoinWaitsForNickServIdentification, .connectUsingSSL, .setInvisibleOnConnect,
		     .serverListItemIsExpanded,
		     .validateServerSideSSLCertificate, .isOutgoingFloodControlEnabled, .migratedToServerListV1Layout: .flag
		}
	}
}
