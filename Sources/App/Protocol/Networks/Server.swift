// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** One endpoint in a connection's server list.

 The password is not part of the value: it lives in the keychain under this
 endpoint's `uniqueIdentifier`, and `pendingServerPassword` only carries an
 edit the user has just made and that has not been flushed there yet. */
nonisolated struct Server: Codable, Sendable, Equatable, Hashable {
	var uniqueIdentifier: String
	var serverAddress: String
	var serverPort: UInt16
	var prefersSecuredConnection: Bool

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
		pendingServerPassword: PendingKeychainSecret = .unchanged
	) {
		self.uniqueIdentifier = uniqueIdentifier
		self.serverAddress = serverAddress
		self.serverPort = serverPort
		self.prefersSecuredConnection = prefersSecuredConnection
		self.pendingServerPassword = pendingServerPassword
	}

	private enum CodingKeys: String, CodingKey {
		case uniqueIdentifier
		case serverAddress
		case serverPort
		case prefersSecuredConnection
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, aliases: [], default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		serverAddress = container.decode(String.self, forKey: .serverAddress, aliases: [], default: "")
		serverPort = container.decode(
			UInt16.self,
			forKey: .serverPort,
			aliases: [],
			default: UInt16(ConnectionDefaults.serverPort)
		)
		prefersSecuredConnection = container.decode(
			Bool.self,
			forKey: .prefersSecuredConnection,
			aliases: [],
			default: false
		)
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encode(prefersSecuredConnection, forKey: .prefersSecuredConnection)
		try container.encode(serverAddress, forKey: .serverAddress)
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		try container.encode(serverPort, forKey: .serverPort)
	}
}

nonisolated extension Server {
	/// A copy under a fresh identity, carrying the password across so the
	/// duplicate does not silently lose it.
	func uniqueCopy() -> Server {
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

	@discardableResult
	mutating func writeServerPasswordToKeychain() -> KeychainWriteResult {
		let result = keychainItem.apply(pendingServerPassword)
		if result == .saved {
			pendingServerPassword = .unchanged
		}
		return result
	}

	@discardableResult
	mutating func destroyServerPasswordKeychainItem() -> KeychainWriteResult {
		pendingServerPassword = .cleared
		let result = keychainItem.apply(pendingServerPassword)
		if result == .saved {
			pendingServerPassword = .unchanged
		}
		return result
	}
}
