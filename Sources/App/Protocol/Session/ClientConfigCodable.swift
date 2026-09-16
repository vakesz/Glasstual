/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

/** How a connection's configuration is spelled on disk.

 The key strings are what earlier releases wrote, down to the ones that no
 longer match the property they set. */
nonisolated extension ClientConfig { // nonisolated: value
	enum CodingKeys: String, CodingKey {
		case dictionaryVersion
		case uniqueIdentifier
		case connectionName
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
		case loginCommands = "onConnectCommands"
		case floodControlDelayTimerInterval
		case floodControlMaximumMessages
		case lastMessageServerTime = "cachedLastServerTimeCapabilityReceivedAtTimestamp"

		case channelList
		case highlightList
		case ignoreList

		/// Written for a build that predates the server list, and read back
		/// when this configuration has no server list of its own.
		case serverAddress
		case serverPort
		case prefersSecuredConnection
		/// Written for a build that predates `cipherSuites`.
		case connectionPrefersModernCiphers
	}

	private typealias DecodingContainer = KeyedDecodingContainer<CodingKeys>

	init(from decoder: any Decoder) throws {
		self.init()

		let container = try decoder.container(keyedBy: CodingKeys.self)
		let storedVersion = container.decode(UInt.self, forKey: .dictionaryVersion, aliases: [], default: 0)

		decodeIdentity(from: container)
		decodeConnection(from: container)
		decodeBehaviour(from: container)
		decodeLists(from: container)

		guard storedVersion != ClientConfigDefaults.dictionaryVersion else {
			return
		}

		/* A configuration written before `addressType` existed said the same
		 thing with a boolean. */
		if connectionPrefersIPv4 {
			addressType = .v4
		}

		applyRateLimitedFloodControlDefaults()
	}

	private mutating func decodeIdentity(from container: DecodingContainer) {
		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, aliases: [], default: "")
		if identifier.isEmpty == false {
			uniqueIdentifier = identifier
		}

		connectionName = container.decode(
			String.self,
			forKey: .connectionName,
			aliases: [],
			default: ApplicationStrings.untitledConnection
		)
		nickname = container.decode(String.self, forKey: .nickname, aliases: [], default: nickname)
		username = container.decode(String.self, forKey: .username, aliases: [], default: username)
		realName = container.decode(String.self, forKey: .realName, aliases: [], default: realName)
		awayNickname = container.decodeOptional(String.self, forKey: .awayNickname) ?? awayNickname
		alternateNicknames = container.decode(
			[String].self,
			forKey: .alternateNicknames,
			aliases: [],
			default: []
		)
		saslMechanismPreference = container.decodeOptional(String.self, forKey: .saslMechanismPreference)
		usesSASL = container.decode(Bool.self, forKey: .usesSASL, aliases: [], default: true)
		saslAuthenticationDisableExternalMechanism = container.decode(
			Bool.self,
			forKey: .saslAuthenticationDisableExternalMechanism,
			aliases: [],
			default: false
		)
		sendAuthenticationRequestsToUserServ = container.decode(
			Bool.self,
			forKey: .sendAuthenticationRequestsToUserServ,
			aliases: [],
			default: false
		)
		identityClientSideCertificate = container.decodeOptional(
			Data.self,
			forKey: .identityClientSideCertificate
		)
	}

	private mutating func decodeConnection(from container: DecodingContainer) {
		addressType = ConnectionAddressType(
			rawValue: container.decode(
				UInt.self,
				forKey: .addressType,
				aliases: [],
				default: ConnectionAddressType.default.rawValue
			)
		) ?? .default
		connectionPrefersIPv4 = container.decode(Bool.self, forKey: .connectionPrefersIPv4, aliases: [], default: false)
		proxyType = ConnectionProxyType(
			rawValue: container.decode(
				UInt.self,
				forKey: .proxyType,
				aliases: [],
				default: ConnectionProxyType.automatic.rawValue
			)
		) ?? .automatic
		proxyAddress = container.decodeOptional(String.self, forKey: .proxyAddress)
		proxyPort = container.decode(
			UInt16.self,
			forKey: .proxyPort,
			aliases: [],
			default: ConnectionDefaults.proxyPort
		)
		proxyUsername = container.decodeOptional(String.self, forKey: .proxyUsername)
		cipherSuites = CipherSuiteCollection(
			rawValue: container.decode(
				UInt.self,
				forKey: .cipherSuites,
				aliases: [],
				default: CipherSuiteCollection.default.rawValue
			)
		) ?? .default
		validateServerCertificateChain = container.decode(
			Bool.self,
			forKey: .validateServerCertificateChain,
			aliases: [],
			default: true
		)
		primaryEncoding = container.decode(
			UInt.self,
			forKey: .primaryEncoding,
			aliases: [],
			default: String.Encoding.utf8.rawValue
		)
		fallbackEncoding = container.decode(
			UInt.self,
			forKey: .fallbackEncoding,
			aliases: [],
			default: String.Encoding.isoLatin1.rawValue
		)

		decodeConnectionPolicies(from: container)
		decodeLegacyEndpoint(from: container)
	}

	private mutating func decodeConnectionPolicies(from container: DecodingContainer) {
		autoConnect = container.decode(Bool.self, forKey: .autoConnect, aliases: [], default: false)
		autoReconnect = container.decode(Bool.self, forKey: .autoReconnect, aliases: [], default: false)
		autoSleepModeDisconnect = container.decode(
			Bool.self,
			forKey: .autoSleepModeDisconnect,
			aliases: [],
			default: true
		)
		performDisconnectOnReachabilityChange = container.decode(
			Bool.self,
			forKey: .performDisconnectOnReachabilityChange,
			aliases: [],
			default: true
		)
		performPongTimer = container.decode(Bool.self, forKey: .performPongTimer, aliases: [], default: true)
		performDisconnectOnPongTimer = container.decode(
			Bool.self,
			forKey: .performDisconnectOnPongTimer,
			aliases: [],
			default: false
		)
		disconnectOnSASLFailure = container.decode(
			Bool.self,
			forKey: .disconnectOnSASLFailure,
			aliases: [],
			default: false
		)
	}

	private mutating func decodeLegacyEndpoint(from container: DecodingContainer) {
		legacyServerAddress = container.decodeOptional(String.self, forKey: .serverAddress)
		legacyServerPort = container.decode(
			UInt16.self,
			forKey: .serverPort,
			aliases: [],
			default: ConnectionDefaults.serverPort
		)
		legacyPrefersSecuredConnection = container.decode(
			Bool.self,
			forKey: .prefersSecuredConnection,
			aliases: [],
			default: false
		)
	}

	private mutating func decodeBehaviour(from container: DecodingContainer) {
		autojoinWaitsForNickServ = container.decode(
			Bool.self,
			forKey: .autojoinWaitsForNickServ,
			aliases: [],
			default: false
		)
		autojoinWaitsForConnectCommands = container.decode(
			Bool.self,
			forKey: .autojoinWaitsForConnectCommands,
			aliases: [],
			default: false
		)
		autojoinDelayAfterConnectCommands = ClientConfigDefaults.autojoinConnectCommandDelay(
			clamping: container.decode(
				TimeInterval.self,
				forKey: .autojoinDelayAfterConnectCommands,
				aliases: [],
				default: ClientConfigDefaults.autojoinConnectCommandDelay
			)
		)
		hideAutojoinDelayedWarnings = container.decode(
			Bool.self,
			forKey: .hideAutojoinDelayedWarnings,
			aliases: [],
			default: false
		)
		hideNetworkUnavailabilityNotices = container.decode(
			Bool.self,
			forKey: .hideNetworkUnavailabilityNotices,
			aliases: [],
			default: false
		)
		sendWhoCommandRequestsToChannels = container.decode(
			Bool.self,
			forKey: .sendWhoCommandRequestsToChannels,
			aliases: [],
			default: true
		)
		setInvisibleModeOnConnect = container.decode(
			Bool.self,
			forKey: .setInvisibleModeOnConnect,
			aliases: [],
			default: false
		)
		runConnectCommandsSilently = container.decode(
			Bool.self,
			forKey: .runConnectCommandsSilently,
			aliases: [],
			default: true
		)
		sidebarItemExpanded = container.decode(Bool.self, forKey: .sidebarItemExpanded, aliases: [], default: true)

		decodeZNCSettings(from: container)
		decodeMessages(from: container)
	}

	private mutating func decodeZNCSettings(from container: DecodingContainer) {
		zncIgnoreConfiguredAutojoin = container.decode(
			Bool.self,
			forKey: .zncIgnoreConfiguredAutojoin,
			aliases: [],
			default: false
		)
		zncIgnorePlaybackNotifications = container.decode(
			Bool.self,
			forKey: .zncIgnorePlaybackNotifications,
			aliases: [],
			default: true
		)
		zncIgnoreUserNotifications = container.decode(
			Bool.self,
			forKey: .zncIgnoreUserNotifications,
			aliases: [],
			default: false
		)
		zncOnlyPlaybackLatest = container.decode(Bool.self, forKey: .zncOnlyPlaybackLatest, aliases: [], default: true)
	}

	private mutating func decodeMessages(from container: DecodingContainer) {
		normalLeavingComment = container.decode(
			String.self,
			forKey: .normalLeavingComment,
			aliases: [],
			default: ApplicationStrings.defaultQuitMessage
		)
		sleepModeLeavingComment = container.decode(
			String.self,
			forKey: .sleepModeLeavingComment,
			aliases: [],
			default: ApplicationStrings.sleepQuitMessage
		)
		ctcpVersionReply = container.decodeOptional(String.self, forKey: .ctcpVersionReply)
		loginCommands = container.decode([String].self, forKey: .loginCommands, aliases: [], default: [])
		floodControlDelayTimerInterval = container.decode(
			UInt.self,
			forKey: .floodControlDelayTimerInterval,
			aliases: [],
			default: ClientConfigDefaults.floodDelay
		)
		floodControlMaximumMessages = container.decode(
			UInt.self,
			forKey: .floodControlMaximumMessages,
			aliases: [],
			default: ClientConfigDefaults.floodMaximum
		)
		lastMessageServerTime = container.decode(
			TimeInterval.self,
			forKey: .lastMessageServerTime,
			aliases: [],
			default: 0
		)
	}

	private mutating func decodeLists(from container: DecodingContainer) {
		serverList = container.decodeOptional([Server].self, forKey: .serverList) ?? []
		channelList = container.decodeOptional([ChannelConfig].self, forKey: .channelList) ?? []
		ignoreList = container.decodeOptional([AddressBookEntry].self, forKey: .ignoreList) ?? []
		// A persisted condition missing its keyword can never match; skip it
		// rather than carrying a half-built entry through the app.
		highlightList = (container.decodeOptional([HighlightMatchCondition].self, forKey: .highlightList) ?? [])
			.filter(\.isWellFormed)
	}
}

/** Writing a connection's configuration.

 Only canonical keys are written, and a setting sitting on its default is left
 out entirely — the same trimming `ce_dictionaryByRemovingDefaults` did, which
 is what keeps a stored client list re-encoding to exactly what is on disk.
 The two keychain-backed passwords are never part of the output. */
nonisolated extension ClientConfig { // nonisolated: value
	private typealias EncodingContainer = KeyedEncodingContainer<CodingKeys>

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encode(ClientConfigDefaults.dictionaryVersion, forKey: .dictionaryVersion)

		try encodeIdentity(into: &container)
		try encodeConnection(into: &container)
		try encodeBehaviour(into: &container)
		try encodeLists(into: &container)
		try encodeLegacyEndpoint(into: &container)
	}

	private func encodeIdentity(into container: inout EncodingContainer) throws {
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		try container.encode(nickname, forKey: .nickname)
		try container.encode(username, forKey: .username)
		try container.encode(realName, forKey: .realName)
		// Written even when empty, as it always has been.
		try container.encode(alternateNicknames, forKey: .alternateNicknames)
		try container.encodeIfPresent(awayNickname, forKey: .awayNickname)
		try container.encodeIfPresent(saslMechanismPreference, forKey: .saslMechanismPreference)
		try encode(usesSASL, forKey: .usesSASL, default: true, &container)
		try container.encodeIfPresent(identityClientSideCertificate, forKey: .identityClientSideCertificate)

		try encode(connectionName, forKey: .connectionName, default: ApplicationStrings.untitledConnection, &container)
		try encode(
			saslAuthenticationDisableExternalMechanism,
			forKey: .saslAuthenticationDisableExternalMechanism,
			default: false,
			&container
		)
		try encode(
			sendAuthenticationRequestsToUserServ,
			forKey: .sendAuthenticationRequestsToUserServ,
			default: false,
			&container
		)
	}

	private func encodeConnection(into container: inout EncodingContainer) throws {
		try container.encodeIfPresent(proxyAddress, forKey: .proxyAddress)
		try container.encodeIfPresent(proxyUsername, forKey: .proxyUsername)
		// Neither of these ever had a default entry, so both are always written.
		try container.encode(connectionPrefersIPv4, forKey: .connectionPrefersIPv4)
		try container.encode(cipherSuites != .none, forKey: .connectionPrefersModernCiphers)

		try encode(
			addressType.rawValue,
			forKey: .addressType,
			default: ConnectionAddressType.default.rawValue,
			&container
		)
		try encode(
			proxyType.rawValue,
			forKey: .proxyType,
			default: ConnectionProxyType.automatic.rawValue,
			&container
		)
		try encode(proxyPort, forKey: .proxyPort, default: ConnectionDefaults.proxyPort, &container)
		try encode(
			cipherSuites.rawValue,
			forKey: .cipherSuites,
			default: CipherSuiteCollection.default.rawValue,
			&container
		)
		try encode(validateServerCertificateChain, forKey: .validateServerCertificateChain, default: true, &container)
		try encode(primaryEncoding, forKey: .primaryEncoding, default: String.Encoding.utf8.rawValue, &container)
		try encode(fallbackEncoding, forKey: .fallbackEncoding, default: String.Encoding.isoLatin1.rawValue, &container)

		try encodeConnectionPolicies(into: &container)
	}

	private func encodeConnectionPolicies(into container: inout EncodingContainer) throws {
		try encode(autoConnect, forKey: .autoConnect, default: false, &container)
		try encode(autoReconnect, forKey: .autoReconnect, default: false, &container)
		try encode(autoSleepModeDisconnect, forKey: .autoSleepModeDisconnect, default: true, &container)
		try encode(
			performDisconnectOnReachabilityChange,
			forKey: .performDisconnectOnReachabilityChange,
			default: true,
			&container
		)
		try encode(performPongTimer, forKey: .performPongTimer, default: true, &container)
		try encode(performDisconnectOnPongTimer, forKey: .performDisconnectOnPongTimer, default: false, &container)
		try encode(disconnectOnSASLFailure, forKey: .disconnectOnSASLFailure, default: false, &container)
	}

	private func encodeBehaviour(into container: inout EncodingContainer) throws {
		try encode(autojoinWaitsForNickServ, forKey: .autojoinWaitsForNickServ, default: false, &container)
		try encode(
			autojoinWaitsForConnectCommands,
			forKey: .autojoinWaitsForConnectCommands,
			default: false,
			&container
		)
		try encode(
			autojoinDelayAfterConnectCommands,
			forKey: .autojoinDelayAfterConnectCommands,
			default: ClientConfigDefaults.autojoinConnectCommandDelay,
			&container
		)
		try encode(hideAutojoinDelayedWarnings, forKey: .hideAutojoinDelayedWarnings, default: false, &container)
		try encode(
			hideNetworkUnavailabilityNotices,
			forKey: .hideNetworkUnavailabilityNotices,
			default: false,
			&container
		)
		try encode(
			sendWhoCommandRequestsToChannels,
			forKey: .sendWhoCommandRequestsToChannels,
			default: true,
			&container
		)
		try encode(setInvisibleModeOnConnect, forKey: .setInvisibleModeOnConnect, default: false, &container)
		try encode(runConnectCommandsSilently, forKey: .runConnectCommandsSilently, default: true, &container)
		try encode(sidebarItemExpanded, forKey: .sidebarItemExpanded, default: true, &container)
		try encode(zncIgnoreConfiguredAutojoin, forKey: .zncIgnoreConfiguredAutojoin, default: false, &container)
		try encode(zncIgnorePlaybackNotifications, forKey: .zncIgnorePlaybackNotifications, default: true, &container)
		try encode(zncIgnoreUserNotifications, forKey: .zncIgnoreUserNotifications, default: false, &container)
		try encode(zncOnlyPlaybackLatest, forKey: .zncOnlyPlaybackLatest, default: true, &container)

		try encodeMessages(into: &container)
	}

	private func encodeMessages(into container: inout EncodingContainer) throws {
		try container.encodeIfPresent(ctcpVersionReply, forKey: .ctcpVersionReply)
		// Written even when empty, as it always has been.
		try container.encode(loginCommands, forKey: .loginCommands)

		try encode(
			normalLeavingComment,
			forKey: .normalLeavingComment,
			default: ApplicationStrings.defaultQuitMessage,
			&container
		)
		try encode(
			sleepModeLeavingComment,
			forKey: .sleepModeLeavingComment,
			default: ApplicationStrings.sleepQuitMessage,
			&container
		)
		try encode(
			floodControlDelayTimerInterval,
			forKey: .floodControlDelayTimerInterval,
			default: ClientConfigDefaults.floodDelay,
			&container
		)
		try encode(
			floodControlMaximumMessages,
			forKey: .floodControlMaximumMessages,
			default: ClientConfigDefaults.floodMaximum,
			&container
		)
		try encode(lastMessageServerTime, forKey: .lastMessageServerTime, default: 0, &container)
	}

	private func encodeLists(into container: inout EncodingContainer) throws {
		if channelList.isEmpty == false {
			try container.encode(channelList, forKey: .channelList)
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

	/// The single endpoint a build without a server list would read.
	private func encodeLegacyEndpoint(into container: inout EncodingContainer) throws {
		try container.encodeIfPresent(serverAddress, forKey: .serverAddress)
		try encode(prefersSecuredConnection, forKey: .prefersSecuredConnection, default: false, &container)
		try encode(serverPort, forKey: .serverPort, default: ConnectionDefaults.serverPort, &container)
	}

	/// Writes `value` unless it is what a reader would assume anyway.
	private func encode<Value: Encodable & Equatable>(
		_ value: Value,
		forKey key: CodingKeys,
		default defaultValue: Value,
		_ container: inout EncodingContainer
	) throws {
		guard value != defaultValue else {
			return
		}

		try container.encode(value, forKey: key)
	}
}
