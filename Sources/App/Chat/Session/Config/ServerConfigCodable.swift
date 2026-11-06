// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** How a connection's configuration is spelled on disk.

 Every key is the name of the property it sets. They are declared rather than
 synthesized so that renaming a property is a deliberate act: the stored session
 list and every exported configuration are keyed by these strings. */
nonisolated extension ServerConfig {
	enum CodingKeys: String, CodingKey {
		case dictionaryVersion
		case uniqueIdentifier
		case connectionName
		case sidebarColor
		case sidebarIcon
		case nickname
		case awayNickname
		case username
		case realName
		case alternateNicknames
		case usesSASL
		case saslMechanismPreference
		case saslAuthenticationDisableExternalMechanism
		case sendAuthenticationRequestsToUserServ
		case identityClientSideCertificate

		case serverList
		case addressType
		case connectionPrefersIPv4
		case proxyType
		case proxyAddress
		case proxyPort
		case proxyUsername
		case cipherSuites
		case validateServerCertificateChain
		case primaryEncoding
		case fallbackEncoding

		case autoConnect
		case autoReconnect
		case autoSleepModeDisconnect
		case performDisconnectOnReachabilityChange
		case performPongTimer
		case performDisconnectOnPongTimer
		case disconnectOnSASLFailure

		case autojoinWaitsForNickServ
		case autojoinWaitsForConnectCommands
		case autojoinDelayAfterConnectCommands
		case hideAutojoinDelayedWarnings
		case hideNetworkUnavailabilityNotices
		case sendWhoCommandRequestsToChannels
		case setInvisibleModeOnConnect
		case runConnectCommandsSilently
		case sidebarItemExpanded
		case zncIgnoreConfiguredAutojoin
		case zncIgnorePlaybackNotifications
		case zncIgnoreUserNotifications
		case zncOnlyPlaybackLatest

		case normalLeavingComment
		case sleepModeLeavingComment
		case ctcpVersionReply
		case loginCommands
		case floodControlDelayTimerInterval
		case floodControlMaximumMessages
		case lastMessageServerTime

		case conversationList
		case highlightList
		case ignoreList
	}

	private typealias DecodingContainer = KeyedDecodingContainer<CodingKeys>

	/** What a key falls back to on both sides of the archive.

	 A decoder assumes these when a key is absent and an encoder leaves out a
	 value that matches one, so the two halves have to agree exactly. They are
	 the property initialisers rather than a second set of literals, which is
	 what makes a changed default reach the archive as one change.

	 The four identity fields are cleared: ``init`` seeds them from the user's
	 settings, which is neither a stored default nor stable for the life of
	 the process. Nothing measures against them — decode falls back to the live
	 values and encode always writes them. */
	private static let codingDefaults: ServerConfig = {
		var defaults = ServerConfig()
		defaults.nickname = ""
		defaults.awayNickname = nil
		defaults.username = ""
		defaults.realName = ""
		return defaults
	}()

	init(from decoder: any Decoder) throws {
		self.init()

		let container = try decoder.container(keyedBy: CodingKeys.self)

		decodeIdentity(from: container)
		decodeConnection(from: container)
		decodeBehaviour(from: container)
		decodeLists(from: container)
	}

	private mutating func decodeIdentity(from container: DecodingContainer) {
		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, default: "")
		if identifier.isEmpty == false {
			uniqueIdentifier = identifier
		}

		connectionName = container.decode(
			String.self,
			forKey: .connectionName,
			default: Self.codingDefaults.connectionName
		)
		sidebarIdentity.color = container.decode(
			ServerIdentityStyle.Color.self, forKey: .sidebarColor, default: .standard
		)
		sidebarIdentity.icon = container.decode(
			ServerIdentityStyle.Icon.self, forKey: .sidebarIcon, default: .network
		)
		nickname = container.decode(String.self, forKey: .nickname, default: nickname)
		username = container.decode(String.self, forKey: .username, default: username)
		realName = container.decode(String.self, forKey: .realName, default: realName)
		awayNickname = container.decodeOptional(String.self, forKey: .awayNickname) ?? awayNickname
		alternateNicknames = container.decode(
			[String].self,
			forKey: .alternateNicknames,
			default: Self.codingDefaults.alternateNicknames
		)
		saslMechanismPreference = container.decodeOptional(String.self, forKey: .saslMechanismPreference)
		usesSASL = container.decode(Bool.self, forKey: .usesSASL, default: Self.codingDefaults.usesSASL)
		saslAuthenticationDisableExternalMechanism = container.decode(
			Bool.self,
			forKey: .saslAuthenticationDisableExternalMechanism,
			default: Self.codingDefaults.saslAuthenticationDisableExternalMechanism
		)
		sendAuthenticationRequestsToUserServ = container.decode(
			Bool.self,
			forKey: .sendAuthenticationRequestsToUserServ,
			default: Self.codingDefaults.sendAuthenticationRequestsToUserServ
		)
		identityClientSideCertificate = container.decodeOptional(
			Data.self,
			forKey: .identityClientSideCertificate
		)
	}

	private mutating func decodeConnection(from container: DecodingContainer) {
		addressType = ConnectionAddressKind(
			rawValue: container.decode(
				UInt.self,
				forKey: .addressType,
				default: Self.codingDefaults.addressType.rawValue
			)
		) ?? .default
		connectionPrefersIPv4 = container.decode(
			Bool.self,
			forKey: .connectionPrefersIPv4,
			default: Self.codingDefaults.connectionPrefersIPv4
		)
		proxyType = ConnectionProxyKind(
			rawValue: container.decode(
				UInt.self,
				forKey: .proxyType,
				default: Self.codingDefaults.proxyType.rawValue
			)
		) ?? .automatic
		proxyAddress = container.decodeOptional(String.self, forKey: .proxyAddress)
		proxyPort = container.decode(UInt16.self, forKey: .proxyPort, default: Self.codingDefaults.proxyPort)
		proxyUsername = container.decodeOptional(String.self, forKey: .proxyUsername)
		cipherSuites = CipherSuiteCollection(
			rawValue: container.decode(
				UInt.self,
				forKey: .cipherSuites,
				default: Self.codingDefaults.cipherSuites.rawValue
			)
		) ?? Self.codingDefaults.cipherSuites
		validateServerCertificateChain = container.decode(
			Bool.self,
			forKey: .validateServerCertificateChain,
			default: Self.codingDefaults.validateServerCertificateChain
		)
		primaryEncoding = container.decode(
			UInt.self,
			forKey: .primaryEncoding,
			default: Self.codingDefaults.primaryEncoding
		)
		fallbackEncoding = container.decode(
			UInt.self,
			forKey: .fallbackEncoding,
			default: Self.codingDefaults.fallbackEncoding
		)

		decodeConnectionPolicies(from: container)
	}

	private mutating func decodeConnectionPolicies(from container: DecodingContainer) {
		autoConnect = container.decode(Bool.self, forKey: .autoConnect, default: Self.codingDefaults.autoConnect)
		autoReconnect = container.decode(Bool.self, forKey: .autoReconnect, default: Self.codingDefaults.autoReconnect)
		autoSleepModeDisconnect = container.decode(
			Bool.self,
			forKey: .autoSleepModeDisconnect,
			default: Self.codingDefaults.autoSleepModeDisconnect
		)
		performDisconnectOnReachabilityChange = container.decode(
			Bool.self,
			forKey: .performDisconnectOnReachabilityChange,
			default: Self.codingDefaults.performDisconnectOnReachabilityChange
		)
		performPongTimer = container.decode(
			Bool.self,
			forKey: .performPongTimer,
			default: Self.codingDefaults.performPongTimer
		)
		performDisconnectOnPongTimer = container.decode(
			Bool.self,
			forKey: .performDisconnectOnPongTimer,
			default: Self.codingDefaults.performDisconnectOnPongTimer
		)
		disconnectOnSASLFailure = container.decode(
			Bool.self,
			forKey: .disconnectOnSASLFailure,
			default: Self.codingDefaults.disconnectOnSASLFailure
		)
	}

	private mutating func decodeBehaviour(from container: DecodingContainer) {
		autojoinWaitsForNickServ = container.decode(
			Bool.self,
			forKey: .autojoinWaitsForNickServ,
			default: Self.codingDefaults.autojoinWaitsForNickServ
		)
		autojoinWaitsForConnectCommands = container.decode(
			Bool.self,
			forKey: .autojoinWaitsForConnectCommands,
			default: Self.codingDefaults.autojoinWaitsForConnectCommands
		)
		autojoinDelayAfterConnectCommands = ServerConfigDefaults.autojoinConnectCommandDelay(
			clamping: container.decode(
				TimeInterval.self,
				forKey: .autojoinDelayAfterConnectCommands,
				default: Self.codingDefaults.autojoinDelayAfterConnectCommands
			)
		)
		hideAutojoinDelayedWarnings = container.decode(
			Bool.self,
			forKey: .hideAutojoinDelayedWarnings,
			default: Self.codingDefaults.hideAutojoinDelayedWarnings
		)
		hideNetworkUnavailabilityNotices = container.decode(
			Bool.self,
			forKey: .hideNetworkUnavailabilityNotices,
			default: Self.codingDefaults.hideNetworkUnavailabilityNotices
		)
		sendWhoCommandRequestsToChannels = container.decode(
			Bool.self,
			forKey: .sendWhoCommandRequestsToChannels,
			default: Self.codingDefaults.sendWhoCommandRequestsToChannels
		)
		setInvisibleModeOnConnect = container.decode(
			Bool.self,
			forKey: .setInvisibleModeOnConnect,
			default: Self.codingDefaults.setInvisibleModeOnConnect
		)
		runConnectCommandsSilently = container.decode(
			Bool.self,
			forKey: .runConnectCommandsSilently,
			default: Self.codingDefaults.runConnectCommandsSilently
		)
		sidebarItemExpanded = container.decode(
			Bool.self,
			forKey: .sidebarItemExpanded,
			default: Self.codingDefaults.sidebarItemExpanded
		)

		decodeZNCSettings(from: container)
		decodeMessages(from: container)
	}

	private mutating func decodeZNCSettings(from container: DecodingContainer) {
		zncIgnoreConfiguredAutojoin = container.decode(
			Bool.self,
			forKey: .zncIgnoreConfiguredAutojoin,
			default: Self.codingDefaults.zncIgnoreConfiguredAutojoin
		)
		zncIgnorePlaybackNotifications = container.decode(
			Bool.self,
			forKey: .zncIgnorePlaybackNotifications,
			default: Self.codingDefaults.zncIgnorePlaybackNotifications
		)
		zncIgnoreUserNotifications = container.decode(
			Bool.self,
			forKey: .zncIgnoreUserNotifications,
			default: Self.codingDefaults.zncIgnoreUserNotifications
		)
		zncOnlyPlaybackLatest = container.decode(
			Bool.self,
			forKey: .zncOnlyPlaybackLatest,
			default: Self.codingDefaults.zncOnlyPlaybackLatest
		)
	}

	private mutating func decodeMessages(from container: DecodingContainer) {
		normalLeavingComment = container.decode(
			String.self,
			forKey: .normalLeavingComment,
			default: Self.codingDefaults.normalLeavingComment
		)
		sleepModeLeavingComment = container.decode(
			String.self,
			forKey: .sleepModeLeavingComment,
			default: Self.codingDefaults.sleepModeLeavingComment
		)
		ctcpVersionReply = container.decodeOptional(String.self, forKey: .ctcpVersionReply)
		loginCommands = container.decode(
			[String].self,
			forKey: .loginCommands,
			default: Self.codingDefaults.loginCommands
		)
		floodControlDelayTimerInterval = container.decode(
			UInt.self,
			forKey: .floodControlDelayTimerInterval,
			default: Self.codingDefaults.floodControlDelayTimerInterval
		)
		floodControlMaximumMessages = container.decode(
			UInt.self,
			forKey: .floodControlMaximumMessages,
			default: Self.codingDefaults.floodControlMaximumMessages
		)
		lastMessageServerTime = container.decode(
			TimeInterval.self,
			forKey: .lastMessageServerTime,
			default: Self.codingDefaults.lastMessageServerTime
		)
	}

	private mutating func decodeLists(from container: DecodingContainer) {
		serverList = container.decodeOptional([ServerEndpoint].self, forKey: .serverList) ?? []
		conversationList = container.decodeOptional([ConversationConfig].self, forKey: .conversationList) ?? []
		ignoreList = container.decodeOptional([AddressBookEntry].self, forKey: .ignoreList) ?? []
		// A persisted condition missing its keyword can never match; skip it
		// rather than carrying a half-built entry through the app.
		highlightList = (container.decodeOptional([HighlightMatchCondition].self, forKey: .highlightList) ?? [])
			.filter(\.isWellFormed)
	}
}

/** Writing a connection's configuration.

 A setting sitting on its default is left out entirely, so a stored session list
 re-encodes to exactly what is on disk and a key added later cannot rewrite
 every configuration. The two keychain-backed passwords are never part of the
 output. */
nonisolated extension ServerConfig {
	private typealias EncodingContainer = KeyedEncodingContainer<CodingKeys>

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encode(ServerConfigDefaults.dictionaryVersion, forKey: .dictionaryVersion)

		try encodeIdentity(into: &container)
		try encodeConnection(into: &container)
		try encodeBehaviour(into: &container)
		try encodeLists(into: &container)
	}

	private func encodeIdentity(into container: inout EncodingContainer) throws {
		/* The nickname, username and real name are always written: ``init`` seeds
		 them from the user's settings, so leaving one out would let a
		 configuration change the next time that setting did. */
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		try container.encode(nickname, forKey: .nickname)
		try container.encode(username, forKey: .username)
		try container.encode(realName, forKey: .realName)
		try container.encodeIfPresent(awayNickname, forKey: .awayNickname)
		try container.encodeIfPresent(saslMechanismPreference, forKey: .saslMechanismPreference)
		try encode(\.usesSASL, forKey: .usesSASL, &container)
		try container.encodeIfPresent(identityClientSideCertificate, forKey: .identityClientSideCertificate)

		try encode(\.alternateNicknames, forKey: .alternateNicknames, &container)
		try encode(\.connectionName, forKey: .connectionName, &container)
		try encode(\.sidebarIdentity.color, forKey: .sidebarColor, &container)
		try encode(\.sidebarIdentity.icon, forKey: .sidebarIcon, &container)
		try encode(\.saslAuthenticationDisableExternalMechanism, forKey: .saslAuthenticationDisableExternalMechanism, &container)
		try encode(\.sendAuthenticationRequestsToUserServ, forKey: .sendAuthenticationRequestsToUserServ, &container)
	}

	private func encodeConnection(into container: inout EncodingContainer) throws {
		try container.encodeIfPresent(proxyAddress, forKey: .proxyAddress)
		try container.encodeIfPresent(proxyUsername, forKey: .proxyUsername)

		try encode(\.connectionPrefersIPv4, forKey: .connectionPrefersIPv4, &container)
		try encode(\.addressType.rawValue, forKey: .addressType, &container)
		try encode(\.proxyType.rawValue, forKey: .proxyType, &container)
		try encode(\.proxyPort, forKey: .proxyPort, &container)
		try encode(\.cipherSuites.rawValue, forKey: .cipherSuites, &container)
		try encode(\.validateServerCertificateChain, forKey: .validateServerCertificateChain, &container)
		try encode(\.primaryEncoding, forKey: .primaryEncoding, &container)
		try encode(\.fallbackEncoding, forKey: .fallbackEncoding, &container)

		try encodeConnectionPolicies(into: &container)
	}

	private func encodeConnectionPolicies(into container: inout EncodingContainer) throws {
		try encode(\.autoConnect, forKey: .autoConnect, &container)
		try encode(\.autoReconnect, forKey: .autoReconnect, &container)
		try encode(\.autoSleepModeDisconnect, forKey: .autoSleepModeDisconnect, &container)
		try encode(\.performDisconnectOnReachabilityChange, forKey: .performDisconnectOnReachabilityChange, &container)
		try encode(\.performPongTimer, forKey: .performPongTimer, &container)
		try encode(\.performDisconnectOnPongTimer, forKey: .performDisconnectOnPongTimer, &container)
		try encode(\.disconnectOnSASLFailure, forKey: .disconnectOnSASLFailure, &container)
	}

	private func encodeBehaviour(into container: inout EncodingContainer) throws {
		try encode(\.autojoinWaitsForNickServ, forKey: .autojoinWaitsForNickServ, &container)
		try encode(\.autojoinWaitsForConnectCommands, forKey: .autojoinWaitsForConnectCommands, &container)
		try encode(\.autojoinDelayAfterConnectCommands, forKey: .autojoinDelayAfterConnectCommands, &container)
		try encode(\.hideAutojoinDelayedWarnings, forKey: .hideAutojoinDelayedWarnings, &container)
		try encode(\.hideNetworkUnavailabilityNotices, forKey: .hideNetworkUnavailabilityNotices, &container)
		try encode(\.sendWhoCommandRequestsToChannels, forKey: .sendWhoCommandRequestsToChannels, &container)
		try encode(\.setInvisibleModeOnConnect, forKey: .setInvisibleModeOnConnect, &container)
		try encode(\.runConnectCommandsSilently, forKey: .runConnectCommandsSilently, &container)
		try encode(\.sidebarItemExpanded, forKey: .sidebarItemExpanded, &container)
		try encode(\.zncIgnoreConfiguredAutojoin, forKey: .zncIgnoreConfiguredAutojoin, &container)
		try encode(\.zncIgnorePlaybackNotifications, forKey: .zncIgnorePlaybackNotifications, &container)
		try encode(\.zncIgnoreUserNotifications, forKey: .zncIgnoreUserNotifications, &container)
		try encode(\.zncOnlyPlaybackLatest, forKey: .zncOnlyPlaybackLatest, &container)

		try encodeMessages(into: &container)
	}

	private func encodeMessages(into container: inout EncodingContainer) throws {
		try container.encodeIfPresent(ctcpVersionReply, forKey: .ctcpVersionReply)
		/* Written even when empty: a configuration export withholds the connect
		 commands by removing the key, so an absent list and an empty list mean
		 different things to an import. */
		try container.encode(loginCommands, forKey: .loginCommands)

		try encode(\.normalLeavingComment, forKey: .normalLeavingComment, &container)
		try encode(\.sleepModeLeavingComment, forKey: .sleepModeLeavingComment, &container)
		try encode(\.floodControlDelayTimerInterval, forKey: .floodControlDelayTimerInterval, &container)
		try encode(\.floodControlMaximumMessages, forKey: .floodControlMaximumMessages, &container)
		try encode(\.lastMessageServerTime, forKey: .lastMessageServerTime, &container)
	}

	private func encodeLists(into container: inout EncodingContainer) throws {
		if conversationList.isEmpty == false {
			try container.encode(conversationList, forKey: .conversationList)
		}

		if highlightList.isEmpty == false {
			try container.encode(highlightList, forKey: .highlightList)
		}

		if ignoreList.isEmpty == false {
			try container.encode(ignoreList, forKey: .ignoreList)
		}

		if serverList.isEmpty == false {
			try container.encode(serverList, forKey: .serverList)
		}
	}

	/// Writes the value at `keyPath` unless it is what a reader would assume
	/// anyway, measured against ``codingDefaults`` so that encode and decode
	/// cannot disagree about what "anyway" means.
	private func encode(
		_ keyPath: KeyPath<ServerConfig, some Encodable & Equatable>,
		forKey key: CodingKeys,
		_ container: inout EncodingContainer
	) throws {
		let value = self[keyPath: keyPath]

		guard value != Self.codingDefaults[keyPath: keyPath] else {
			return
		}

		try container.encode(value, forKey: key)
	}
}
