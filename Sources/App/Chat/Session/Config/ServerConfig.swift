// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
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
	var sidebarIdentity = ServerIdentityStyle()
	var nickname = ""
	var awayNickname: String?
	var username = ""
	var realName = ""
	var alternateNicknames: [String] = []
	/// A connection authenticates with SASL unless it says otherwise, so the
	/// stored dictionary only ever names this to switch it off.
	var usesSASL = true
	/// The mechanism SASL tries first, or `nil` to choose automatically.
	var saslMechanismPreference: SASLMechanism?
	/// Stops SASL falling back to other mechanisms when the preferred one is
	/// refused or cannot be used. Meaningless without a preference.
	var saslUsesOnlyPreferredMechanism = false
	/// Signs in again by itself when the server re-offers SASL to a registered
	/// connection that is not signed in, as services do after a split.
	var saslReauthenticatesAutomatically = true
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
	/// Whether a soju bouncer's networks are listed here as servers of their own.
	var bouncerDiscoversNetworks = true
	/// Whether the bouncer connection itself leaves the sidebar once it has
	/// networks to show.
	var bouncerHidesParent = false
	/// Set on a connection that is one network of a bouncer account, and only
	/// there. Such a connection is made by discovery, not by the user.
	var bouncerNetwork: BouncerNetworkBinding?

	var normalLeavingComment = ApplicationStrings.defaultQuitMessage
	var sleepModeLeavingComment = ApplicationStrings.sleepQuitMessage
	var ctcpVersionReply: String?
	var loginCommands: [String] = []
	var floodControlDelayTimerInterval = ServerConfigDefaults.floodDelay
	var floodControlMaximumMessages = ServerConfigDefaults.floodMaximum
	var lastMessageServerTime: TimeInterval = 0
	/// The profile the user chose for themselves on this server, set again on
	/// connect where the server's copy differs. `nil` until they chose one.
	var serverProfile: ServerProfilePreference?

	// MARK: - Owned lists

	var conversationList: [ConversationConfig] = []
	var highlightList: [HighlightMatchCondition] = []
	var ignoreList: [AddressBookEntry] = []

	// MARK: - Secrets and transient state

	/// An unflushed edit to the nickname password. Never encoded.
	var pendingNicknamePassword: PendingKeychainSecret = .unchanged
	/// An unflushed edit to the proxy password. Never encoded.
	var pendingProxyPassword: PendingKeychainSecret = .unchanged
	/// An unflushed edit to the SASL ECDSA signing key, as ``ECDSASigningKey`` stores
	/// it. Never encoded.
	var pendingSASLSigningKey: PendingKeychainSecret = .unchanged
	/// An unflushed edit to the SASL OAUTHBEARER token. Never encoded.
	var pendingSASLBearerToken: PendingKeychainSecret = .unchanged

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

	var serverTransport: ServerTransport {
		serverList.first?.transport ?? .irc
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
	/// The identifier the connection's own secrets are filed under. A bouncer
	/// network has none of its own: it signs in as its parent account, so it
	/// reads the parent's items rather than keeping a second copy of them.
	var credentialIdentifier: String {
		bouncerNetwork?.parentIdentifier ?? uniqueIdentifier
	}

	var nicknamePasswordKeychainItem: KeychainItem {
		.nicknamePassword(credentialIdentifier)
	}

	var proxyPasswordKeychainItem: KeychainItem {
		.proxyPassword(credentialIdentifier)
	}

	var saslSigningKeyKeychainItem: KeychainItem {
		.saslSigningKey(credentialIdentifier)
	}

	var saslBearerTokenKeychainItem: KeychainItem {
		.saslBearerToken(credentialIdentifier)
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
		copy.pendingSASLSigningKey = pendingSASLSigningKey.detached(from: saslSigningKeyKeychainItem.password)
		copy.pendingSASLBearerToken = pendingSASLBearerToken.detached(from: saslBearerTokenKeychainItem.password)
		copy.conversationList = conversationList.map { $0.uniqueCopy() }
		copy.highlightList = highlightList.map { $0.uniqueCopy() }
		copy.ignoreList = ignoreList.map { $0.uniqueCopy() }
		copy.serverList = serverList.map { $0.uniqueCopy() }
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}
}

// MARK: - Re-identification

nonisolated extension ServerConfig {
	/** The same configuration under identities no keychain item is filed under.

	 Every secret is keyed on the identifier of the model that owns it, so a
	 configuration that must not inherit the secrets of another one with the
	 same endpoint needs fresh identifiers all the way down. Unlike
	 ``uniqueCopy()`` this carries no secret across, and the identifiers are
	 derived rather than random: the same configuration and `context` always
	 name the same identities, so importing one file twice finds what the first
	 import made instead of adding another network. */
	func reidentified(derivedFrom context: String) -> ServerConfig {
		func derived(_ identifier: String) -> String {
			Self.derivedIdentifier(from: identifier, context: context)
		}
		var copy = self
		copy.uniqueIdentifier = derived(uniqueIdentifier)
		copy.pendingNicknamePassword = .unchanged
		copy.pendingProxyPassword = .unchanged
		copy.pendingSASLSigningKey = .unchanged
		copy.pendingSASLBearerToken = .unchanged
		copy.serverList = serverList.map {
			var server = $0
			server.uniqueIdentifier = derived(server.uniqueIdentifier)
			server.pendingServerPassword = .unchanged
			return server
		}
		copy.conversationList = conversationList.map {
			var conversation = $0
			conversation.uniqueIdentifier = derived(conversation.uniqueIdentifier)
			conversation.pendingSecretKey = .unchanged
			return conversation
		}
		copy.highlightList = highlightList.map {
			var highlight = $0
			highlight.uniqueIdentifier = derived(highlight.uniqueIdentifier)
			return highlight
		}
		copy.ignoreList = ignoreList.map {
			var entry = $0
			entry.uniqueIdentifier = derived(entry.uniqueIdentifier)
			return entry
		}

		return copy
	}

	/// A version 5 style UUID over the identifier and the context it is derived in.
	static func derivedIdentifier(from identifier: String, context: String) -> String {
		var bytes = Array(SHA256.hash(data: Data("glasstual.reidentified/\(context)/\(identifier)".utf8)).prefix(16))
		bytes[6] = (bytes[6] & 0x0F) | 0x50
		bytes[8] = (bytes[8] & 0x3F) | 0x80

		return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }.uuidString
	}
}
