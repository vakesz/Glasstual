// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated enum ServerConfigDefaults {
	/// Which spelling of the stored dictionary this build writes. Version 1 is
	/// the only one it reads: an import carrying anything higher is refused.
	static let dictionaryVersion: UInt = 1
	static let floodDelay: UInt = 2
	static let floodMaximum: UInt = 6
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
nonisolated struct ServerConfig: Codable, Equatable, Sendable {
	// MARK: - Identity

	var uniqueIdentifier = UUID().uuidString
	var connectionName = ApplicationStrings.untitledConnection
	var nickname = ""
	var awayNickname: String?
	var username = ""
	var realName = ""
	var alternateNicknames: [String] = []
	/// A connection authenticates with SASL unless it says otherwise, so the
	/// stored dictionary only ever names this to switch it off.
	var usesSASL = true
	var saslMechanismPreference: String?
	var saslAuthenticationDisableExternalMechanism = false
	var sendAuthenticationRequestsToUserServ = false
	var identityClientSideCertificate: Data?

	// MARK: - Connection

	var serverList: [ServerEndpoint] = []
	var addressType = ConnectionAddressKind.default
	var connectionPrefersIPv4 = false
	var proxyType = ConnectionProxyKind.automatic
	var proxyAddress: String?
	var proxyPort = ConnectionDefaults.proxyPort
	var proxyUsername: String?
	/** Which cipher suites the connection offers.

	 A fresh connection takes the platform's own group, which is what the system
	 keeps current. The two named lists are fixed and only narrow it; they stay
	 for a user who has to reach an old server, and are not what anyone gets by
	 default. Suites with no forward secrecy are in neither — the transport
	 offers those by itself, once, to a server that accepts nothing else. */
	var cipherSuites = CipherSuiteCollection.system
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
	var autojoinDelayAfterConnectCommands = ServerConfigDefaults.autojoinConnectCommandDelay
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
	var floodControlDelayTimerInterval = ServerConfigDefaults.floodDelay
	var floodControlMaximumMessages = ServerConfigDefaults.floodMaximum
	var lastMessageServerTime: TimeInterval = 0

	// MARK: - Owned lists

	var conversationList: [ConversationConfig] = []
	var highlightList: [HighlightMatchCondition] = []
	var ignoreList: [AddressBookEntry] = []

	// MARK: - Secrets and transient state

	/// An unflushed edit to the nickname password. Never encoded.
	var pendingNicknamePassword: PendingKeychainSecret = .unchanged
	/// An unflushed edit to the proxy password. Never encoded.
	var pendingProxyPassword: PendingKeychainSecret = .unchanged

	init(connectionName: String? = nil) {
		self.connectionName = connectionName ?? ApplicationStrings.untitledConnection
		nickname = SettingsKeys.Identity.nickname.detachedValue
		awayNickname = SettingsKeys.Identity.awayNickname.detachedStoredValue
		username = SettingsKeys.Identity.username.detachedValue
		realName = SettingsKeys.Identity.realName.detachedValue
	}
}

// MARK: - Derived values

nonisolated extension ServerConfig {
	/// The endpoint the connection would use: the first in the server list, or
	/// nothing when the list is empty.
	var serverAddress: String? {
		serverList.first?.serverAddress
	}

	var serverPort: UInt16 {
		serverList.first?.serverPort ?? UInt16(ConnectionDefaults.serverPort)
	}

	var prefersSecuredConnection: Bool {
		serverList.first?.prefersSecuredConnection ?? false
	}

	/// `true` when the connection is pinned to IPv4 twice over, which the
	/// server-properties sheet warns about.
	var showConnectionPrefersIPv4Warning: Bool {
		addressType == .v4 && connectionPrefersIPv4
	}

	/// The dictionary shape the stored session list uses.
	var dictionaryValue: [String: PropertyListValue] {
		PropertyListModel.encode(self)
	}
}

// MARK: - Keychain-backed secrets

nonisolated extension ServerConfig {
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
}

// MARK: - Copying

nonisolated extension ServerConfig {
	/** A duplicate under fresh identities, all the way down.

	 Every keychain item is keyed on the identifier being replaced, so each
	 secret is read back under the old one before the new one is minted; the
	 duplicate writes them out under its own identifier when it is next saved.
	 Without this the duplicate silently loses its passwords. */
	func uniqueCopy() -> ServerConfig {
		var copy = self
		copy.pendingNicknamePassword = pendingNicknamePassword.detached(from: nicknamePasswordFromKeychain)
		copy.pendingProxyPassword = pendingProxyPassword.detached(from: proxyPasswordFromKeychain)
		copy.conversationList = conversationList.map { $0.uniqueCopy() }
		copy.highlightList = highlightList.map { $0.uniqueCopy() }
		copy.ignoreList = ignoreList.map { $0.uniqueCopy() }
		copy.serverList = serverList.map { $0.uniqueCopy() }
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}
}
