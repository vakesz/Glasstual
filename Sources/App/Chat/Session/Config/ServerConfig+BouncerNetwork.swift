// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation

/** What ties a connection to one network of a soju account.

 The parent is the connection the account was discovered on. The network is
 the identifier the bouncer gave it, which `BOUNCER BIND` names before
 registration completes. */
nonisolated struct BouncerNetworkBinding: Codable, Equatable, Sendable {
	var parentIdentifier: String
	var networkIdentifier: String
	/// The bouncer no longer lists the network. Its conversations and history
	/// stay readable, but the connection cannot be opened again.
	var isRemoved = false

	private enum CodingKeys: String, CodingKey {
		case parentIdentifier
		case networkIdentifier
		case isRemoved
	}

	init(parentIdentifier: String, networkIdentifier: String, isRemoved: Bool = false) {
		self.parentIdentifier = parentIdentifier
		self.networkIdentifier = networkIdentifier
		self.isRemoved = isRemoved
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		parentIdentifier = try container.decode(String.self, forKey: .parentIdentifier)
		networkIdentifier = try container.decode(String.self, forKey: .networkIdentifier)
		isRemoved = try container.decodeIfPresent(Bool.self, forKey: .isRemoved) ?? false
	}
}

nonisolated extension ServerConfig {
	/** The identifier a network's connection keeps across launches and across
	 rediscovery.

	 It is derived from the parent and the bouncer's identifier, so a network
	 that disappears and comes back finds its conversations, logs and history
	 under the same key. The shape is a version 5 style UUID. */
	static func bouncerNetworkConnectionIdentifier(parent: String, network: String) -> String {
		var bytes = Array(SHA256.hash(data: Data("glasstual.bouncer-network/\(parent)/\(network)".utf8)).prefix(16))
		bytes[6] = (bytes[6] & 0x0F) | 0x50
		bytes[8] = (bytes[8] & 0x3F) | 0x80
		let hex = bytes.map { String($0, radix: 16, uppercase: true).leftPadded(to: 2) }
		let groups = [0 ..< 4, 4 ..< 6, 6 ..< 8, 8 ..< 10, 10 ..< 16]
		return groups.map { hex[$0].joined() }.joined(separator: "-")
	}

	/// The connection that stands for `network` on this account.
	func derivingBouncerNetwork(_ network: BouncerNetwork) -> ServerConfig {
		var child = ServerConfig()
		child.sidebarIdentity = sidebarIdentity
		child.connectionName = network.displayName
		child.uniqueIdentifier = Self.bouncerNetworkConnectionIdentifier(
			parent: uniqueIdentifier, network: network.id
		)
		child.bouncerNetwork = BouncerNetworkBinding(parentIdentifier: uniqueIdentifier, networkIdentifier: network.id)
		return child.inheritingConnectionSettings(from: self)
	}

	/** This network connection with the parent's identity, TLS, SASL, proxy and
	 connection policy laid over it.

	 What stays is what belongs to the network alone: its identifier, name,
	 sidebar look, conversations, rules, connect commands and read position.
	 Secrets are not copied. The connection reads the parent's, because
	 ``credentialIdentifier`` points at them. */
	func inheritingConnectionSettings(from parent: ServerConfig) -> ServerConfig {
		var merged = parent
		merged.uniqueIdentifier = uniqueIdentifier
		merged.connectionName = connectionName
		merged.sidebarIdentity = sidebarIdentity
		merged.bouncerNetwork = bouncerNetwork
		merged.bouncerDiscoversNetworks = false
		merged.bouncerHidesParent = false
		merged.conversationList = conversationList
		merged.highlightList = highlightList
		merged.ignoreList = ignoreList
		merged.loginCommands = loginCommands
		merged.sidebarItemExpanded = sidebarItemExpanded
		merged.lastMessageServerTime = lastMessageServerTime
		merged.pendingNicknamePassword = .unchanged
		merged.pendingProxyPassword = .unchanged
		merged.pendingSASLSigningKey = .unchanged
		merged.serverList = parent.serverList.map {
			var server = $0
			server.pendingServerPassword = .unchanged
			return server
		}
		return merged
	}
}

extension ServerConfig {
	/// The keychain items this connection may delete when it is removed. A
	/// bouncer network shares its account's secrets and owns only its channels'.
	var ownedKeychainItems: [KeychainItem] {
		guard bouncerNetwork != nil else { return keychainItems }
		return conversationList.map(\.keychainItem)
	}
}

private nonisolated extension String {
	func leftPadded(to length: Int) -> String {
		String(repeating: "0", count: max(0, length - count)) + self
	}
}
