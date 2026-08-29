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
import os

private nonisolated let clientConfigMigrationLogger = Logger( // nonisolated: let
	subsystem: "com.vakesz.glasstual",
	category: "Migration"
)

/// Reading a version 0 configuration: the one written before the settings were
/// renamed, before flood control became two plain numbers, and before a
/// connection had a list of endpoints instead of a single address.
nonisolated extension ClientConfig { // nonisolated: value
	private typealias Container = KeyedDecodingContainer<CodingKeys>

	mutating func migrateVersionZero(from container: KeyedDecodingContainer<CodingKeys>) {
		migrateRenamedIdentityKeys(from: container)
		migrateRenamedConnectionKeys(from: container)
		migrateFloodControl(from: container)
		migrateProxyPassword(from: container)
		migrateCipherSuites(from: container)
		migrateServerList(from: container)
	}

	private mutating func migrateRenamedIdentityKeys(from container: Container) {
		alternateNicknames = container.decode(
			[String].self,
			forKey: .identityAlternateNicknames,
			aliases: [],
			default: alternateNicknames
		)
		awayNickname = container.decodeOptional(String.self, forKey: .identityAwayNickname) ?? awayNickname
		nickname = container.decode(String.self, forKey: .identityNickname, aliases: [], default: nickname)
		realName = container.decode(String.self, forKey: .identityRealname, aliases: [], default: realName)
		username = container.decode(String.self, forKey: .identityUsername, aliases: [], default: username)
		identityClientSideCertificate = container.decodeOptional(Data.self, forKey: .identitySSLCertificate)
			?? identityClientSideCertificate
	}

	private mutating func migrateRenamedConnectionKeys(from container: Container) {
		autoConnect = container.decode(Bool.self, forKey: .connectOnLaunch, aliases: [], default: autoConnect)
		autoReconnect = container.decode(Bool.self, forKey: .connectOnDisconnect, aliases: [], default: autoReconnect)
		autoSleepModeDisconnect = container.decode(
			Bool.self,
			forKey: .disconnectOnSleepMode,
			aliases: [],
			default: autoSleepModeDisconnect
		)
		autojoinWaitsForNickServ = container.decode(
			Bool.self,
			forKey: .autojoinWaitsForNickServIdentification,
			aliases: [],
			default: autojoinWaitsForNickServ
		)
		legacyPrefersSecuredConnection = container.decode(
			Bool.self,
			forKey: .connectUsingSSL,
			aliases: [],
			default: legacyPrefersSecuredConnection
		)
		setInvisibleModeOnConnect = container.decode(
			Bool.self,
			forKey: .setInvisibleOnConnect,
			aliases: [],
			default: setInvisibleModeOnConnect
		)
		sidebarItemExpanded = container.decode(
			Bool.self,
			forKey: .serverListItemIsExpanded,
			aliases: [],
			default: sidebarItemExpanded
		)
		validateServerCertificateChain = container.decode(
			Bool.self,
			forKey: .validateServerSideSSLCertificate,
			aliases: [],
			default: validateServerCertificateChain
		)

		migrateRenamedMessageKeys(from: container)
	}

	private mutating func migrateRenamedMessageKeys(from container: Container) {
		normalLeavingComment = container.decode(
			String.self,
			forKey: .connectionDisconnectDefaultMessage,
			aliases: [],
			default: normalLeavingComment
		)
		sleepModeLeavingComment = container.decode(
			String.self,
			forKey: .connectionDisconnectSleepModeMessage,
			aliases: [],
			default: sleepModeLeavingComment
		)
		proxyAddress = container.decodeOptional(String.self, forKey: .proxyServerAddress) ?? proxyAddress
		proxyUsername = container.decodeOptional(String.self, forKey: .proxyServerUsername) ?? proxyUsername
		primaryEncoding = container.decode(
			UInt.self,
			forKey: .characterEncodingDefault,
			aliases: [],
			default: primaryEncoding
		)
		fallbackEncoding = container.decode(
			UInt.self,
			forKey: .characterEncodingFallback,
			aliases: [],
			default: fallbackEncoding
		)
		proxyType = IRCConnectionProxyType(
			rawValue: container.decode(UInt.self, forKey: .proxyServerType, aliases: [], default: proxyType.rawValue)
		) ?? proxyType
		proxyPort = container.decode(UInt16.self, forKey: .proxyServerPort, aliases: [], default: proxyPort)
		lastMessageServerTime = container.decode(
			TimeInterval.self,
			forKey: .cachedLastServerTimeCapacityReceivedAtTimestamp,
			aliases: [],
			default: lastMessageServerTime
		)
	}

	/// Flood control used to be a nested dictionary plus a separate switch;
	/// turning it off meant the loosest delay and the largest burst.
	private mutating func migrateFloodControl(from container: Container) {
		var disabled = false

		if let floodControl = container.decodeOptional(LegacyFloodControl.self, forKey: .floodControl) {
			disabled = floodControl.serviceEnabled == false
			floodControlDelayTimerInterval = floodControl.delayTimerInterval ?? floodControlDelayTimerInterval
			floodControlMaximumMessages = floodControl.maximumMessageCount ?? floodControlMaximumMessages
		}

		if container.decodeOptional(Bool.self, forKey: .isOutgoingFloodControlEnabled) == false {
			disabled = true
		}

		guard disabled else {
			return
		}

		floodControlDelayTimerInterval = ClientConfigDefaults.minimumFloodDelay
		floodControlMaximumMessages = ClientConfigDefaults.maximumFloodMessages
	}

	/// The proxy password used to sit in the property list in the clear. It is
	/// moved to the keychain on the first read and never written back.
	private mutating func migrateProxyPassword(from container: Container) {
		guard let password = container.decodeOptional(String.self, forKey: .proxyServerPassword) else {
			return
		}

		pendingProxyPassword = password
		writeProxyPasswordToKeychain()
	}

	/// A build that predates named cipher suites recorded only whether it
	/// wanted the modern ones.
	private mutating func migrateCipherSuites(from container: Container) {
		guard container.contains(.cipherSuites) == false,
		      container.decodeOptional(Bool.self, forKey: .connectionPrefersModernCiphers) == false
		else {
			return
		}

		cipherSuites = .none
	}

	/// The single stored endpoint becomes the first entry of the server list,
	/// carrying its keychain item across to the new identifier.
	private mutating func migrateServerList(from container: Container) {
		guard container.decodeOptional(Bool.self, forKey: .migratedToServerListV1Layout) != true,
		      serverList.isEmpty
		else {
			return
		}

		guard let address = legacyServerAddress, (address as NSString).isValidInternetAddress else {
			clientConfigMigrationLogger.debug("Server-list migration cancelled because the stored address is invalid")
			return
		}

		let port = container.decode(UInt16.self, forKey: .serverPort, aliases: [], default: 0)
		guard port > 0 else {
			clientConfigMigrationLogger.debug("Server-list migration cancelled because the stored port is invalid")
			return
		}

		var server = Server(
			serverAddress: address,
			serverPort: port,
			prefersSecuredConnection: legacyPrefersSecuredConnection,
			pendingServerPassword: KeychainItem.serverPassword(uniqueIdentifier).password
		)
		server.writeServerPasswordToKeychain()

		serverList = [server]
		migratedServerPasswordPendingDestroy = true
	}
}

/// The nested dictionary a version 0 configuration stored flood control in.
private nonisolated struct LegacyFloodControl: Decodable { // nonisolated: value
	var serviceEnabled: Bool?
	var delayTimerInterval: UInt?
	var maximumMessageCount: UInt?
}
