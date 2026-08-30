/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// `Server` reads and writes the same four keys earlier releases put in the
/// client list, so an existing preferences file survives the move to Codable.
@Suite("Server property-list round trip")
struct IRCServerCodableTests {
	@Test("A stored endpoint decodes into the same values")
	func decodesCanonicalKeys() throws {
		let server = try #require(PropertyListModel.decode(Server.self, from: [
			"uniqueIdentifier": "endpoint-1",
			"serverAddress": "irc.example.test",
			"serverPort": 6697,
			"prefersSecuredConnection": true,
		]))

		#expect(server.uniqueIdentifier == "endpoint-1")
		#expect(server.serverAddress == "irc.example.test")
		#expect(server.serverPort == 6697)
		#expect(server.prefersSecuredConnection)
	}

	@Test("Encoding writes exactly the four canonical keys")
	func encodesCanonicalKeys() {
		let encoded = PropertyListModel.encode(
			Server(
				uniqueIdentifier: "endpoint-1",
				serverAddress: "irc.example.test",
				serverPort: 6697,
				prefersSecuredConnection: true,
				pendingServerPassword: "never-written"
			)
		)

		#expect(Set(encoded.keys) == [
			"uniqueIdentifier",
			"serverAddress",
			"serverPort",
			"prefersSecuredConnection",
		])
		#expect(encoded["serverAddress"]?.string == "irc.example.test")
		#expect(encoded["serverPort"]?.integer == 6697)
		#expect(encoded["prefersSecuredConnection"]?.boolean == true)
	}

	@Test("A dictionary written by the previous release re-encodes unchanged")
	func roundTripsAStoredDictionary() throws {
		// Captured from the class-based `Server.dictionaryValue`.
		let fixture: [String: PropertyListValue] = [
			"prefersSecuredConnection": true,
			"serverAddress": "irc.example.test",
			"uniqueIdentifier": "8B2F4C1A-0000-4000-8000-000000000001",
			"serverPort": 6697,
		]

		let server = try #require(PropertyListModel.decode(Server.self, from: fixture))

		#expect(PropertyListModel.encode(server) == fixture)
	}

	@Test("A missing port falls back to the default rather than zero")
	func missingPortUsesTheDefault() throws {
		let server = try #require(PropertyListModel.decode(Server.self, from: [
			"serverAddress": "irc.example.test",
		]))

		#expect(server.serverPort == UInt16(IRCConnectionDefaults.serverPort))
		#expect(server.uniqueIdentifier.isEmpty == false)
	}

	@Test("The password is not part of the encoded value")
	func passwordIsNeverEncoded() {
		var server = Server(serverAddress: "irc.example.test")
		server.serverPassword = "hunter2"

		#expect(PropertyListModel.encode(server)["serverPassword"] == nil)
		#expect(server.pendingServerPassword == "hunter2")
	}
}
