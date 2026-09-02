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

nonisolated enum ClientConfigDefaults { // nonisolated: value
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
	/// How long an autojoin waits after the connect commands were sent, for a
	/// connection that asks it to. Long enough for a services reply to land.
	static let autojoinConnectCommandDelay: TimeInterval = 3
	static let maximumAutojoinConnectCommandDelay: TimeInterval = 60
	/// Networks that rate-limit hard enough to need the reduced flood settings.
	static let rateLimitedServerSuffix = ".freenode.net"
}

/** Everything one IRC connection is configured with.

 The two secrets this carries — the nickname password and the proxy password —
 live in the keychain under `uniqueIdentifier` and are never encoded. The
 `pending…` properties carry the edit waiting to reach the keychain: one the
 user has just typed, one read back out of the keychain so a duplicate can
 rewrite it under its own identifier, or the removal an emptied field asks
 for. */
public nonisolated struct ClientConfig: Codable, Equatable, Sendable { // nonisolated: value
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
	/// Holds the autojoin back until the connect commands below have been sent,
	/// for a server where a channel only accepts the connection afterwards.
	public var autojoinWaitsForConnectCommands = false
	/** How long that wait lasts, in seconds.

	 The commands are sent, not answered: whatever a server replies arrives
	 later and out of band, so what the wait can offer is a pause long enough
	 for the reply to land. It applies only when there are commands to wait
	 for. */
	public var autojoinDelayAfterConnectCommands = ClientConfigDefaults.autojoinConnectCommandDelay
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

	/// An unflushed edit to the nickname password. Never encoded.
	public var pendingNicknamePassword: PendingKeychainSecret = .unchanged
	/// An unflushed edit to the proxy password. Never encoded.
	public var pendingProxyPassword: PendingKeychainSecret = .unchanged

	/** The single address, port and TLS flag that releases before the server
	 list stored. They are still written out so an older build can read the
	 file, and are only read back when there is no server list. */
	var legacyServerAddress: String?
	var legacyServerPort = ClientConfigDefaults.serverPort
	var legacyPrefersSecuredConnection = false

	public init(connectionName: String? = nil) {
		self.connectionName = connectionName ?? ApplicationStrings.untitledConnection
		nickname = Preferences.Identity.nickname.detachedValue
		awayNickname = Preferences.Identity.awayNickname.detachedStoredValue
		username = Preferences.Identity.username.detachedValue
		realName = Preferences.Identity.realName.detachedValue
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

public nonisolated extension ClientConfig { // nonisolated: value
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
	var dictionaryValue: [String: PropertyListValue] {
		PropertyListModel.encode(self)
	}
}

// MARK: - Keychain-backed secrets

public nonisolated extension ClientConfig { // nonisolated: value
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
		get { pendingNicknamePassword.value(orStored: nicknamePasswordFromKeychain) }
		set { pendingNicknamePassword = PendingKeychainSecret(newValue) }
	}

	var proxyPassword: String? {
		get { pendingProxyPassword.value(orStored: proxyPasswordFromKeychain) }
		set { pendingProxyPassword = PendingKeychainSecret(newValue) }
	}

	mutating func writeNicknamePasswordToKeychain() {
		nicknamePasswordKeychainItem.apply(pendingNicknamePassword)
		pendingNicknamePassword = .unchanged
	}

	mutating func writeProxyPasswordToKeychain() {
		proxyPasswordKeychainItem.apply(pendingProxyPassword)
		pendingProxyPassword = .unchanged
	}

	mutating func destroyNicknamePasswordKeychainItem() {
		nicknamePasswordKeychainItem.delete()
		pendingNicknamePassword = .unchanged
	}

	mutating func destroyProxyPasswordKeychainItem() {
		proxyPasswordKeychainItem.delete()
		pendingProxyPassword = .unchanged
	}
}

// MARK: - Copying and merging

public nonisolated extension ClientConfig { // nonisolated: value
	/** A duplicate under fresh identities, all the way down.

	 Every keychain item is keyed on the identifier being replaced, so each
	 secret is read back under the old one before the new one is minted; the
	 duplicate writes them out under its own identifier when it is next saved.
	 Without this the duplicate silently loses its passwords. */
	func uniqueCopy() -> ClientConfig {
		var copy = self
		copy.pendingNicknamePassword = pendingNicknamePassword.detached(from: nicknamePasswordFromKeychain)
		copy.pendingProxyPassword = pendingProxyPassword.detached(from: proxyPasswordFromKeychain)
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
		config.pendingNicknamePassword = second.pendingNicknamePassword.merged(over: first.pendingNicknamePassword)
		config.pendingProxyPassword = second.pendingProxyPassword.merged(over: first.pendingProxyPassword)

		return config
	}
}

// MARK: - Flood control

nonisolated extension ClientConfig { // nonisolated: value
	/** Networks that rate-limit hard enough to need the reduced settings get
	 them the first time a configuration naming one is read. Encoding always
	 measures against the standard defaults, so a reduced value is written out
	 verbatim and survives the round trip. */
	var usesRateLimitedFloodControl: Bool {
		serverList.contains { $0.serverAddress.hasSuffix(ClientConfigDefaults.rateLimitedServerSuffix) }
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
