// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private nonisolated let serverEndpointLogger = Logger(subsystem: LogSubsystem.current, category: "ServerEndpoint")

/** One endpoint in a connection's server list.

 The password is not part of the value: it lives in the keychain under this
 endpoint's `uniqueIdentifier`, and `pendingServerPassword` only carries an
 edit the user has just made and that has not been flushed there yet. */
nonisolated struct ServerEndpoint: Codable, Sendable, Equatable, Hashable {
	var uniqueIdentifier: String
	var serverAddress: String
	var serverPort: UInt16
	var prefersSecuredConnection: Bool
	/// IRC over TCP or TLS, or IRC over a WebSocket.
	var transport: ServerTransport
	/// The WebSocket request target. Kept, but unused, for an IRC entry, so a
	/// switch back and forth does not lose it.
	var webSocketPath: String

	/** An unflushed edit to the password: one waiting to be written, one read
	 back out of the keychain so that a duplicate can carry it to its own
	 identifier, or the removal an emptied field asks for. It is never
	 encoded — see `serverPassword`. */
	var pendingServerPassword: PendingKeychainSecret = .unchanged

	init(
		uniqueIdentifier: String = UUID().uuidString,
		serverAddress: String = "",
		serverPort: UInt16 = UInt16(ConnectionDefaults.serverPort),
		prefersSecuredConnection: Bool = false,
		transport: ServerTransport = .irc,
		webSocketPath: String = "/",
		pendingServerPassword: PendingKeychainSecret = .unchanged
	) {
		self.uniqueIdentifier = uniqueIdentifier
		self.serverAddress = serverAddress
		self.serverPort = serverPort
		self.prefersSecuredConnection = prefersSecuredConnection
		self.transport = transport
		self.webSocketPath = webSocketPath
		self.pendingServerPassword = pendingServerPassword
	}

	/// An entry for a `ws://` or `wss://` URL.
	init(webSocketAddress address: WebSocketAddress) {
		self.init(
			serverAddress: address.host,
			serverPort: address.port,
			prefersSecuredConnection: address.secured,
			transport: .webSocket,
			webSocketPath: address.path
		)
	}

	enum CodingKeys: String, CodingKey {
		case uniqueIdentifier
		case serverAddress
		case serverPort
		case prefersSecuredConnection
		case transport
		case webSocketPath
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		serverAddress = container.decode(String.self, forKey: .serverAddress, default: "")
		serverPort = container.decode(
			UInt16.self,
			forKey: .serverPort,
			default: UInt16(ConnectionDefaults.serverPort)
		)
		prefersSecuredConnection = container.decode(Bool.self, forKey: .prefersSecuredConnection, default: false)
		transport = Self.decodedTransport(from: container)
		let path = container.decode(String.self, forKey: .webSocketPath, default: "/")
		webSocketPath = ServerTransport.isValidWebSocketPath(path) ? path : "/"
	}

	/// An absent transport is an entry from before there was a choice. One this
	/// build does not know is dialled as IRC, which is what that build would do.
	private static func decodedTransport(from container: KeyedDecodingContainer<CodingKeys>) -> ServerTransport {
		guard let name = try? container.decodeIfPresent(String.self, forKey: .transport) else { return .irc }
		guard let transport = ServerTransport(rawValue: name) else {
			serverEndpointLogger.error("Unknown server transport; connecting over IRC")
			return .irc
		}
		return transport
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encode(prefersSecuredConnection, forKey: .prefersSecuredConnection)
		try container.encode(serverAddress, forKey: .serverAddress)
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		try container.encode(serverPort, forKey: .serverPort)
		/* Only a WebSocket entry names its transport, so an IRC entry is stored
		 exactly as it was before there was a choice. */
		if transport != .irc {
			try container.encode(transport, forKey: .transport)
			try container.encode(webSocketPath, forKey: .webSocketPath)
		}
	}
}

nonisolated extension ServerEndpoint {
	/// A copy under a fresh identity, carrying the password across so the
	/// duplicate does not silently lose it.
	func uniqueCopy() -> ServerEndpoint {
		var copy = self
		copy.pendingServerPassword = pendingServerPassword.detached(from: serverPasswordFromKeychain)
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}

	var keychainItem: KeychainItem {
		.serverPassword(uniqueIdentifier)
	}

	var serverPasswordFromKeychain: String? {
		keychainItem.password
	}

	/// The password to connect with: an unflushed edit if there is one, and
	/// otherwise whatever the keychain holds.
	var serverPassword: String? {
		get { pendingServerPassword.value(orStored: serverPasswordFromKeychain) }
		set { pendingServerPassword = PendingKeychainSecret(newValue) }
	}
}

nonisolated extension ServerEndpoint {
	/// Changes the transport, moving a port that is unset or still the old
	/// transport's default to the new one's: a port someone chose is kept.
	mutating func switchTransport(to newTransport: ServerTransport) {
		if serverPort == 0 || serverPort == transport.defaultPort(secured: prefersSecuredConnection) {
			serverPort = newTransport.defaultPort(secured: prefersSecuredConnection)
		}
		transport = newTransport
	}

	/// The `ws://` or `wss://` URL a WebSocket entry dials, and nil for IRC.
	var webSocketURL: String? {
		guard transport == .webSocket else { return nil }
		return WebSocketAddress.url(
			host: serverAddress,
			port: serverPort,
			secured: prefersSecuredConnection,
			path: webSocketPath
		)
	}
}
