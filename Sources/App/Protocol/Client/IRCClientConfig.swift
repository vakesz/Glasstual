/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

nonisolated enum ClientConfigDefaults {
	/// Bumped whenever a stored dictionary needs migrating. A dictionary that
	/// carries version 0 is run through the legacy migration on load.
	static let dictionaryVersion: UInt = 710
	static let proxyPort: UInt16 = 1080
	static let serverPort: UInt16 = 6667
	static let floodDelay: UInt = 2
	static let floodMaximum: UInt = 6
	static let limitedFloodDelay: UInt = 2
	static let limitedFloodMaximum: UInt = 2
	static let minimumFloodDelay: UInt = 1
	static let maximumFloodDelay: UInt = 60
	static let minimumFloodMessages: UInt = 1
	static let maximumFloodMessages: UInt = 60
	/// Networks that rate-limit hard enough to need the reduced flood settings.
	static let rateLimitedServerSuffix = ".freenode.net"
}

/** Everything one IRC connection is configured with.

 The two secrets this carries — the nickname password and the proxy password —
 live in the keychain under `uniqueIdentifier` and are never encoded. The
 `pending…` properties hold one the user has just typed, or one read back out
 of the keychain so a duplicate can rewrite it under its own identifier. */
public nonisolated struct ClientConfig: Codable, Equatable {
	// MARK: - Identity

	public var uniqueIdentifier = UUID().uuidString
	public var connectionName = ApplicationStrings.untitledConnection
	public var nickname = ""
	public var awayNickname: String?
	public var username = ""
	public var realName = ""
	public var alternateNicknames: [String] = []
	public var saslMechanismPreference: String?
	public var saslAuthenticationDisableExternalMechanism = false
	public var sendAuthenticationRequestsToUserServ = false
	public var identityClientSideCertificate: Data?

	// MARK: - Connection

	public var serverList: [Server] = []
	public var addressType = IRCConnectionAddressType.default
	public var connectionPrefersIPv4 = false
	public var proxyType = IRCConnectionProxyType.automatic
	public var proxyAddress: String?
	public var proxyPort = ClientConfigDefaults.proxyPort
	public var proxyUsername: String?
	public var cipherSuites = CipherSuiteCollection.default
	public var validateServerCertificateChain = true
	public var primaryEncoding = String.Encoding.utf8.rawValue
	public var fallbackEncoding = String.Encoding.isoLatin1.rawValue

	public var autoConnect = false
	public var autoReconnect = false
	public var autoSleepModeDisconnect = true
	public var performDisconnectOnReachabilityChange = true
	public var performPongTimer = true
	public var performDisconnectOnPongTimer = false
	/// Ends the connection when the server rejects SASL (904, 905 or 906)
	/// instead of completing registration unauthenticated.
	public var disconnectOnSASLFailure = false

	// MARK: - Behaviour

	public var autojoinWaitsForNickServ = false
	public var hideAutojoinDelayedWarnings = false
	public var hideNetworkUnavailabilityNotices = false
	public var sendWhoCommandRequestsToChannels = true
	public var setInvisibleModeOnConnect = false
	public var runConnectCommandsSilently = true
	public var sidebarItemExpanded = true
	public var zncIgnoreConfiguredAutojoin = false
	public var zncIgnorePlaybackNotifications = true
	public var zncIgnoreUserNotifications = false
	public var zncOnlyPlaybackLatest = true

	public var normalLeavingComment = ApplicationStrings.defaultQuitMessage
	public var sleepModeLeavingComment = ApplicationStrings.sleepQuitMessage
	public var ctcpVersionReply: String?
	public var loginCommands: [String] = []
	public var floodControlDelayTimerInterval = ClientConfigDefaults.floodDelay
	public var floodControlMaximumMessages = ClientConfigDefaults.floodMaximum
	public var lastMessageServerTime: TimeInterval = 0

	// MARK: - Owned lists

	public var channelList: [ChannelConfig] = []
	public var highlightList: [HighlightMatchCondition] = []
	public var ignoreList: [AddressBookEntry] = []

	// MARK: - Secrets and transient state

	/// A nickname password waiting to be written to the keychain. Never encoded.
	public var pendingNicknamePassword: String?
	/// A proxy password waiting to be written to the keychain. Never encoded.
	public var pendingProxyPassword: String?

	/** Set when a pre-server-list configuration's server password was moved to
	 the endpoint that replaced it; the old item is deleted once the new one has
	 been written. */
	var migratedServerPasswordPendingDestroy = false

	/** The single address, port and TLS flag that releases before the server
	 list stored. They are still written out so an older build can read the
	 file, and are only read back when there is no server list. */
	var legacyServerAddress: String?
	var legacyServerPort = ClientConfigDefaults.serverPort
	var legacyPrefersSecuredConnection = false

	public init(connectionName: String? = nil) {
		self.connectionName = connectionName ?? ApplicationStrings.untitledConnection
		nickname = TextualPreferences.defaultNickname()
		awayNickname = TextualPreferences.defaultAwayNickname()
		username = TextualPreferences.defaultUsername()
		realName = TextualPreferences.defaultRealName()
	}

	/// A configuration seeded from a preconfigured network.
	public static func newConfig(with network: Network) -> ClientConfig {
		var config = ClientConfig(connectionName: network.networkName)
		config.serverList = [
			Server(
				serverAddress: network.serverAddress,
				serverPort: network.serverPort,
				prefersSecuredConnection: network.prefersSecuredConnection
			),
		]

		return config
	}
}

// MARK: - Derived values

public nonisolated extension ClientConfig {
	/// The address the connection would use, preferring the server list and
	/// falling back to what a pre-server-list configuration stored.
	var serverAddress: String? {
		serverList.first?.serverAddress ?? legacyServerAddress
	}

	var serverPort: UInt16 {
		serverList.first?.serverPort ?? legacyServerPort
	}

	var prefersSecuredConnection: Bool {
		serverList.first?.prefersSecuredConnection ?? legacyPrefersSecuredConnection
	}

	/// `true` when the connection is pinned to IPv4 twice over, which the
	/// server-properties sheet warns about.
	var showConnectionPrefersIPv4Warning: Bool {
		addressType == .v4 && connectionPrefersIPv4
	}

	/// The dictionary shape the stored client list uses.
	var dictionaryValue: [String: Any] {
		PropertyListModel.encode(self)
	}
}

// MARK: - Keychain-backed secrets

public nonisolated extension ClientConfig {
	var nicknamePasswordKeychainItem: KeychainItem {
		.nicknamePassword(uniqueIdentifier)
	}

	var proxyPasswordKeychainItem: KeychainItem {
		.proxyPassword(uniqueIdentifier)
	}

	var nicknamePasswordFromKeychain: String? {
		nicknamePasswordKeychainItem.password
	}

	var proxyPasswordFromKeychain: String? {
		proxyPasswordKeychainItem.password
	}

	/// The nickname password: an unflushed edit if there is one, and otherwise
	/// whatever the keychain holds.
	var nicknamePassword: String? {
		get { pendingNicknamePassword ?? nicknamePasswordFromKeychain }
		set { pendingNicknamePassword = newValue }
	}

	var proxyPassword: String? {
		get { pendingProxyPassword ?? proxyPasswordFromKeychain }
		set { pendingProxyPassword = newValue }
	}

	mutating func writeNicknamePasswordToKeychain() {
		guard let pendingNicknamePassword else {
			return
		}

		nicknamePasswordKeychainItem.write(pendingNicknamePassword)
		self.pendingNicknamePassword = nil
	}

	mutating func writeProxyPasswordToKeychain() {
		guard let pendingProxyPassword else {
			return
		}

		proxyPasswordKeychainItem.write(pendingProxyPassword)
		self.pendingProxyPassword = nil
	}

	mutating func destroyNicknamePasswordKeychainItem() {
		nicknamePasswordKeychainItem.delete()
		pendingNicknamePassword = nil
	}

	mutating func destroyProxyPasswordKeychainItem() {
		proxyPasswordKeychainItem.delete()
		pendingProxyPassword = nil
	}

	/// Removes the pre-server-list server password once the endpoint that
	/// replaced it has written its own copy.
	mutating func destroyServerPasswordKeychainItemAfterMigration() {
		guard migratedServerPasswordPendingDestroy else {
			return
		}

		migratedServerPasswordPendingDestroy = false
		KeychainItem.serverPassword(uniqueIdentifier).delete()
	}
}

// MARK: - Copying and merging

public nonisolated extension ClientConfig {
	/** A duplicate under fresh identities, all the way down.

	 Every keychain item is keyed on the identifier being replaced, so each
	 secret is read back under the old one before the new one is minted; the
	 duplicate writes them out under its own identifier when it is next saved.
	 Without this the duplicate silently loses its passwords. */
	func uniqueCopy() -> ClientConfig {
		var copy = self
		copy.pendingNicknamePassword = pendingNicknamePassword ?? nicknamePasswordFromKeychain
		copy.pendingProxyPassword = pendingProxyPassword ?? proxyPasswordFromKeychain
		copy.channelList = channelList.map { $0.uniqueCopy() }
		copy.highlightList = highlightList.map { $0.uniqueCopy() }
		copy.ignoreList = ignoreList.map { $0.uniqueCopy() }
		copy.serverList = serverList.map { $0.uniqueCopy() }
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}

	/** `second`'s settings laid over `first`'s.

	 The merge happens between the stored dictionaries, so a setting `second`
	 does not carry keeps the value `first` had. The class this replaced
	 assigned every optional unconditionally and so wiped `awayNickname`,
	 `ctcpVersionReply`, `proxyAddress`, `proxyUsername` and
	 `saslMechanismPreference` whenever `second` left them out. */
	static func merging(_ first: ClientConfig, with second: ClientConfig) -> ClientConfig {
		var merged = PropertyListModel.encode(first)
		merged.merge(PropertyListModel.encode(second)) { _, replacement in replacement }

		var config = PropertyListModel.decode(ClientConfig.self, from: merged) ?? second
		config.pendingNicknamePassword = second.pendingNicknamePassword ?? first.pendingNicknamePassword
		config.pendingProxyPassword = second.pendingProxyPassword ?? first.pendingProxyPassword

		return config
	}
}

// MARK: - Flood control

nonisolated extension ClientConfig {
	/** Networks that rate-limit hard enough to need the reduced settings get
	 them as their default, both when the configuration is read and when it is
	 written back out. */
	var usesRateLimitedFloodControl: Bool {
		serverList.contains { $0.serverAddress.hasSuffix(ClientConfigDefaults.rateLimitedServerSuffix) }
	}

	var defaultFloodControlDelay: UInt {
		usesRateLimitedFloodControl ? ClientConfigDefaults.limitedFloodDelay : ClientConfigDefaults.floodDelay
	}

	var defaultFloodControlMaximum: UInt {
		usesRateLimitedFloodControl ? ClientConfigDefaults.limitedFloodMaximum : ClientConfigDefaults.floodMaximum
	}

	/// Moves a configuration still sitting on the standard defaults onto the
	/// reduced ones once its server list names a rate-limited network.
	mutating func applyRateLimitedFloodControlDefaults() {
		guard floodControlDelayTimerInterval == ClientConfigDefaults.floodDelay,
		      floodControlMaximumMessages == ClientConfigDefaults.floodMaximum,
		      usesRateLimitedFloodControl
		else {
			return
		}

		floodControlDelayTimerInterval = ClientConfigDefaults.limitedFloodDelay
		floodControlMaximumMessages = ClientConfigDefaults.limitedFloodMaximum
	}
}

public typealias IRCClientConfig = ClientConfig
