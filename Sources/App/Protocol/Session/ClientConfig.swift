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

	/** The autojoin pause as a number of seconds the rest of the app can use.

	 The Settings stepper offers `0 ... maximumAutojoinConnectCommandDelay` and
	 an imported configuration is checked against the same range, which leaves a
	 hand-edited `plist` as the one way something else reaches the property. It
	 is bounded where the configuration is read so that every later use — the
	 label that narrows it to an `Int`, the sleep that turns it into a
	 `Duration` — is reading seconds. `min`/`max` pass NaN through, so the
	 finiteness check comes first. */
	static func autojoinConnectCommandDelay(clamping value: TimeInterval) -> TimeInterval {
		guard value.isFinite else {
			return autojoinConnectCommandDelay
		}

		return min(max(value, 0), maximumAutojoinConnectCommandDelay)
	}
}

/** Everything one IRC connection is configured with.

 The two secrets this carries — the nickname password and the proxy password —
 live in the keychain under `uniqueIdentifier` and are never encoded. The
 `pending…` properties carry the edit waiting to reach the keychain: one the
 user has just typed, one read back out of the keychain so a duplicate can
 rewrite it under its own identifier, or the removal an emptied field asks
 for. */
nonisolated struct ClientConfig: Codable, Equatable, Sendable { // nonisolated: value
	// MARK: - Identity

	var uniqueIdentifier = UUID().uuidString
	var connectionName = ApplicationStrings.untitledConnection
	var nickname = ""
	var awayNickname: String?
	var username = ""
	var realName = ""
	var alternateNicknames: [String] = []
	/// Absence in older configurations means SASL remains enabled.
	var usesSASL = true
	var saslMechanismPreference: String?
	var saslAuthenticationDisableExternalMechanism = false
	var sendAuthenticationRequestsToUserServ = false
	var identityClientSideCertificate: Data?

	// MARK: - Connection

	var serverList: [Server] = []
	var addressType = ConnectionAddressType.default
	var connectionPrefersIPv4 = false
	var proxyType = ConnectionProxyType.automatic
	var proxyAddress: String?
	var proxyPort = ClientConfigDefaults.proxyPort
	var proxyUsername: String?
	var cipherSuites = CipherSuiteCollection.default
	var validateServerCertificateChain = true
	var primaryEncoding = String.Encoding.utf8.rawValue
	var fallbackEncoding = String.Encoding.isoLatin1.rawValue

	var autoConnect = false
	var autoReconnect = false
	var autoSleepModeDisconnect = true
	var performDisconnectOnReachabilityChange = true
	var performPongTimer = true
	var performDisconnectOnPongTimer = false
	/// Ends the connection when the server rejects SASL (904, 905 or 906)
	/// instead of completing registration unauthenticated.
	var disconnectOnSASLFailure = false

	// MARK: - Behaviour

	var autojoinWaitsForNickServ = false
	/// Holds the autojoin back until the connect commands below have been sent,
	/// for a server where a channel only accepts the connection afterwards.
	var autojoinWaitsForConnectCommands = false
	/** How long that wait lasts, in seconds.

	 The commands are sent, not answered: whatever a server replies arrives
	 later and out of band, so what the wait can offer is a pause long enough
	 for the reply to land. It applies only when there are commands to wait
	 for. */
	var autojoinDelayAfterConnectCommands = ClientConfigDefaults.autojoinConnectCommandDelay
	var hideAutojoinDelayedWarnings = false
	var hideNetworkUnavailabilityNotices = false
	var sendWhoCommandRequestsToChannels = true
	var setInvisibleModeOnConnect = false
	var runConnectCommandsSilently = true
	var sidebarItemExpanded = true
	var zncIgnoreConfiguredAutojoin = false
	var zncIgnorePlaybackNotifications = true
	var zncIgnoreUserNotifications = false
	var zncOnlyPlaybackLatest = true

	var normalLeavingComment = ApplicationStrings.defaultQuitMessage
	var sleepModeLeavingComment = ApplicationStrings.sleepQuitMessage
	var ctcpVersionReply: String?
	var loginCommands: [String] = []
	var floodControlDelayTimerInterval = ClientConfigDefaults.floodDelay
	var floodControlMaximumMessages = ClientConfigDefaults.floodMaximum
	var lastMessageServerTime: TimeInterval = 0

	// MARK: - Owned lists

	var channelList: [ChannelConfig] = []
	var highlightList: [HighlightMatchCondition] = []
	var ignoreList: [AddressBookEntry] = []

	// MARK: - Secrets and transient state

	/// An unflushed edit to the nickname password. Never encoded.
	var pendingNicknamePassword: PendingKeychainSecret = .unchanged
	/// An unflushed edit to the proxy password. Never encoded.
	var pendingProxyPassword: PendingKeychainSecret = .unchanged

	/** The single address, port and TLS flag that releases before the server
	 list stored. They are still written out so an older build can read the
	 file, and are only read back when there is no server list. */
	var legacyServerAddress: String?
	var legacyServerPort = ClientConfigDefaults.serverPort
	var legacyPrefersSecuredConnection = false

	init(connectionName: String? = nil) {
		self.connectionName = connectionName ?? ApplicationStrings.untitledConnection
		nickname = Preferences.Identity.nickname.detachedValue
		awayNickname = Preferences.Identity.awayNickname.detachedStoredValue
		username = Preferences.Identity.username.detachedValue
		realName = Preferences.Identity.realName.detachedValue
	}

	/// A configuration seeded from a preconfigured network.
	static func newConfig(with network: Network) -> ClientConfig {
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

nonisolated extension ClientConfig { // nonisolated: value
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

nonisolated extension ClientConfig { // nonisolated: value
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

	@discardableResult
	mutating func writeNicknamePasswordToKeychain() -> KeychainWriteResult {
		let result = nicknamePasswordKeychainItem.apply(pendingNicknamePassword)
		if result == .saved {
			pendingNicknamePassword = .unchanged
		}
		return result
	}

	@discardableResult
	mutating func writeProxyPasswordToKeychain() -> KeychainWriteResult {
		let result = proxyPasswordKeychainItem.apply(pendingProxyPassword)
		if result == .saved {
			pendingProxyPassword = .unchanged
		}
		return result
	}

	@discardableResult
	mutating func destroyNicknamePasswordKeychainItem() -> KeychainWriteResult {
		pendingNicknamePassword = .cleared
		let result = nicknamePasswordKeychainItem.apply(pendingNicknamePassword)
		if result == .saved {
			pendingNicknamePassword = .unchanged
		}
		return result
	}

	@discardableResult
	mutating func destroyProxyPasswordKeychainItem() -> KeychainWriteResult {
		pendingProxyPassword = .cleared
		let result = proxyPasswordKeychainItem.apply(pendingProxyPassword)
		if result == .saved {
			pendingProxyPassword = .unchanged
		}
		return result
	}
}

// MARK: - Copying

nonisolated extension ClientConfig { // nonisolated: value
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
}

// MARK: - Flood control

nonisolated extension ClientConfig { // nonisolated: value
	/** Networks that rate-limit hard enough to need the reduced settings get
	 them the first time a configuration naming one is read. Encoding always
	 measures against the standard defaults, so a reduced value is written out
	 verbatim and survives the round trip. */
	var usesRateLimitedFloodControl: Bool {
		serverList.contains { $0.serverAddress.hasSuffix(ServerQuirks.rateLimitedServerSuffix) }
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
