/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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

/** One endpoint in a connection's server list.

 The password is not part of the value: it lives in the keychain under this
 endpoint's `uniqueIdentifier`, and `pendingServerPassword` only holds one that
 the user has just typed and that has not been flushed there yet. */
public nonisolated struct Server: Codable, Sendable, Equatable, Hashable {
	public var uniqueIdentifier: String
	public var serverAddress: String
	public var serverPort: UInt16
	public var prefersSecuredConnection: Bool

	/** A password waiting to be written to the keychain, or one read back out
	 of it so that a duplicate can carry it to its own identifier. It is never
	 encoded — see `serverPassword`. */
	public var pendingServerPassword: String?

	public init(
		uniqueIdentifier: String = UUID().uuidString,
		serverAddress: String = "",
		serverPort: UInt16 = UInt16(IRCConnectionDefaults.serverPort),
		prefersSecuredConnection: Bool = false,
		pendingServerPassword: String? = nil
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

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, aliases: [], default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		serverAddress = container.decode(String.self, forKey: .serverAddress, aliases: [], default: "")
		serverPort = container.decode(
			UInt16.self,
			forKey: .serverPort,
			aliases: [],
			default: UInt16(IRCConnectionDefaults.serverPort)
		)
		prefersSecuredConnection = container.decode(
			Bool.self,
			forKey: .prefersSecuredConnection,
			aliases: [],
			default: false
		)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encode(prefersSecuredConnection, forKey: .prefersSecuredConnection)
		try container.encode(serverAddress, forKey: .serverAddress)
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		try container.encode(serverPort, forKey: .serverPort)
	}
}

public nonisolated extension Server {
	/// A copy under a fresh identity, carrying the password across so the
	/// duplicate does not silently lose it.
	func uniqueCopy() -> Server {
		var copy = self
		copy.pendingServerPassword = pendingServerPassword ?? serverPasswordFromKeychain
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
		get { pendingServerPassword ?? serverPasswordFromKeychain }
		set { pendingServerPassword = newValue }
	}

	mutating func writeServerPasswordToKeychain() {
		guard let pendingServerPassword else {
			return
		}

		keychainItem.write(pendingServerPassword)
		self.pendingServerPassword = nil
	}

	mutating func destroyServerPasswordKeychainItem() {
		keychainItem.delete()
		pendingServerPassword = nil
	}
}
