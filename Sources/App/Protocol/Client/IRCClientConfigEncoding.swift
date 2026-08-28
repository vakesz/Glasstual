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
import GlasstualPluginKit

/** Writing a connection's configuration.

 Only canonical keys are written, and a setting sitting on its default is left
 out entirely — the same trimming `ce_dictionaryByRemovingDefaults` did, which
 is what keeps a stored client list re-encoding to exactly what is on disk.
 The two keychain-backed passwords are never part of the output. */
nonisolated extension ClientConfig {
	private typealias Container = KeyedEncodingContainer<CodingKeys>

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encode(ClientConfigDefaults.dictionaryVersion, forKey: .dictionaryVersion)

		try encodeIdentity(into: &container)
		try encodeConnection(into: &container)
		try encodeBehaviour(into: &container)
		try encodeLists(into: &container)
		try encodeLegacyEndpoint(into: &container)
	}

	private func encodeIdentity(into container: inout Container) throws {
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		try container.encode(nickname, forKey: .nickname)
		try container.encode(username, forKey: .username)
		try container.encode(realName, forKey: .realName)
		// Written even when empty, as it always has been.
		try container.encode(alternateNicknames, forKey: .alternateNicknames)
		try container.encodeIfPresent(awayNickname, forKey: .awayNickname)
		try container.encodeIfPresent(saslMechanismPreference, forKey: .saslMechanismPreference)
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

	private func encodeConnection(into container: inout Container) throws {
		try container.encodeIfPresent(proxyAddress, forKey: .proxyAddress)
		try container.encodeIfPresent(proxyUsername, forKey: .proxyUsername)
		// Neither of these ever had a default entry, so both are always written.
		try container.encode(connectionPrefersIPv4, forKey: .connectionPrefersIPv4)
		try container.encode(cipherSuites != .none, forKey: .connectionPrefersModernCiphers)

		try encode(
			addressType.rawValue,
			forKey: .addressType,
			default: IRCConnectionAddressType.default.rawValue,
			&container
		)
		try encode(
			proxyType.rawValue,
			forKey: .proxyType,
			default: IRCConnectionProxyType.automatic.rawValue,
			&container
		)
		try encode(proxyPort, forKey: .proxyPort, default: ClientConfigDefaults.proxyPort, &container)
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

	private func encodeConnectionPolicies(into container: inout Container) throws {
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

	private func encodeBehaviour(into container: inout Container) throws {
		try encode(autojoinWaitsForNickServ, forKey: .autojoinWaitsForNickServ, default: false, &container)
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

	private func encodeMessages(into container: inout Container) throws {
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
			default: defaultFloodControlDelay,
			&container
		)
		try encode(
			floodControlMaximumMessages,
			forKey: .floodControlMaximumMessages,
			default: defaultFloodControlMaximum,
			&container
		)
		try encode(lastMessageServerTime, forKey: .lastMessageServerTime, default: 0, &container)
	}

	private func encodeLists(into container: inout Container) throws {
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
	private func encodeLegacyEndpoint(into container: inout Container) throws {
		try container.encodeIfPresent(serverAddress, forKey: .serverAddress)
		try encode(prefersSecuredConnection, forKey: .prefersSecuredConnection, default: false, &container)
		try encode(serverPort, forKey: .serverPort, default: ClientConfigDefaults.serverPort, &container)
	}

	/// Writes `value` unless it is what a reader would assume anyway.
	private func encode<Value: Encodable & Equatable>(
		_ value: Value,
		forKey key: CodingKeys,
		default defaultValue: Value,
		_ container: inout Container
	) throws {
		guard value != defaultValue else {
			return
		}

		try container.encode(value, forKey: key)
	}
}
