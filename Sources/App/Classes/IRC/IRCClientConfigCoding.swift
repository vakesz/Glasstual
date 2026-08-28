/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import GlasstualPluginKit

/** How a connection's configuration is spelled on disk.

 The key strings are what earlier releases wrote, down to the ones that no
 longer match the property they set. Anything under "Legacy spellings" is only
 read, and only from a version 0 dictionary. */
nonisolated extension ClientConfig {
	enum CodingKeys: String, CodingKey {
		case dictionaryVersion
		case uniqueIdentifier
		case connectionName
		case nickname
		case awayNickname
		case username
		case realName
		case alternateNicknames
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

		// Legacy spellings, read from a version 0 dictionary only.
		case identityAlternateNicknames
		case connectOnLaunch
		case connectOnDisconnect
		case disconnectOnSleepMode
		case autojoinWaitsForNickServIdentification
		case connectUsingSSL
		case setInvisibleOnConnect
		case serverListItemIsExpanded
		case validateServerSideSSLCertificate
		case identitySSLCertificate = "IdentitySSLCertificate"
		case identityAwayNickname
		case identityNickname
		case connectionDisconnectDefaultMessage
		case proxyServerAddress
		case proxyServerUsername
		case proxyServerPassword
		case proxyServerType
		case proxyServerPort
		case identityRealname
		case connectionDisconnectSleepModeMessage
		case identityUsername
		case characterEncodingDefault
		case characterEncodingFallback
		case cachedLastServerTimeCapacityReceivedAtTimestamp
		case floodControl
		case isOutgoingFloodControlEnabled
		case migratedToServerListV1Layout
	}

	private typealias Container = KeyedDecodingContainer<CodingKeys>

	public init(from decoder: any Decoder) throws {
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

		if storedVersion == 0 {
			migrateVersionZero(from: container)
		}

		applyRateLimitedFloodControlDefaults()
	}

	private mutating func decodeIdentity(from container: Container) {
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

	private mutating func decodeConnection(from container: Container) {
		addressType = IRCConnectionAddressType(
			rawValue: container.decode(
				UInt.self,
				forKey: .addressType,
				aliases: [],
				default: IRCConnectionAddressType.default.rawValue
			)
		) ?? .default
		connectionPrefersIPv4 = container.decode(Bool.self, forKey: .connectionPrefersIPv4, aliases: [], default: false)
		proxyType = IRCConnectionProxyType(
			rawValue: container.decode(
				UInt.self,
				forKey: .proxyType,
				aliases: [],
				default: IRCConnectionProxyType.automatic.rawValue
			)
		) ?? .automatic
		proxyAddress = container.decodeOptional(String.self, forKey: .proxyAddress)
		proxyPort = container.decode(
			UInt16.self,
			forKey: .proxyPort,
			aliases: [],
			default: ClientConfigDefaults.proxyPort
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

	private mutating func decodeConnectionPolicies(from container: Container) {
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

	private mutating func decodeLegacyEndpoint(from container: Container) {
		legacyServerAddress = container.decodeOptional(String.self, forKey: .serverAddress)
		legacyServerPort = container.decode(
			UInt16.self,
			forKey: .serverPort,
			aliases: [],
			default: ClientConfigDefaults.serverPort
		)
		legacyPrefersSecuredConnection = container.decode(
			Bool.self,
			forKey: .prefersSecuredConnection,
			aliases: [],
			default: false
		)
	}

	private mutating func decodeBehaviour(from container: Container) {
		autojoinWaitsForNickServ = container.decode(
			Bool.self,
			forKey: .autojoinWaitsForNickServ,
			aliases: [],
			default: false
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

	private mutating func decodeZNCSettings(from container: Container) {
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

	private mutating func decodeMessages(from container: Container) {
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

	private mutating func decodeLists(from container: Container) {
		serverList = container.decodeOptional([Server].self, forKey: .serverList) ?? []
		channelList = container.decodeOptional([ChannelConfig].self, forKey: .channelList) ?? []
		ignoreList = container.decodeOptional([AddressBookEntry].self, forKey: .ignoreList) ?? []
		// A persisted condition missing its keyword can never match; skip it
		// rather than carrying a half-built entry through the app.
		highlightList = (container.decodeOptional([HighlightMatchCondition].self, forKey: .highlightList) ?? [])
			.filter(\.isWellFormed)
	}
}
