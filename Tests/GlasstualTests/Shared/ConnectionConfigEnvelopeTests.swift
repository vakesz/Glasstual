// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// The connection host receives its configuration as a value inside an
/// `NSSecureCoding` envelope, so everything it needs has to survive the
/// archive-and-unarchive that `NSXPCConnection` performs.
@Suite("Connection configuration XPC envelope")
struct ConnectionConfigEnvelopeTests {
	private func sampleConfig() -> ConnectionConfig {
		var config = ConnectionConfig()
		config.serverAddress = "irc.example.test"
		config.serverPort = 6697
		config.addressType = .v6
		config.connectionPrefersSecuredConnection = true
		config.cipherSuites = .intermediate
		config.connectionShouldValidateCertificateChain = true
		config.connectionRequiresTrustedCertificate = true
		config.identityClientSideCertificate = Data([0x01, 0x02, 0x03])
		config.proxyType = .socks5
		config.proxyAddress = "proxy.example.test"
		config.proxyPort = 1081
		config.proxyUsername = "user"
		config.proxyPassword = "hunter2"
		config.setFloodControl(delayInterval: 5, maximumMessages: 3)

		return config
	}

	private func roundTrip(_ config: ConnectionConfig) throws -> ConnectionConfig {
		let archived = try NSKeyedArchiver.archivedData(
			withRootObject: ConnectionConfigEnvelope(config: config),
			requiringSecureCoding: true
		)
		let unarchived = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: ConnectionConfigEnvelope.self,
			from: archived
		)

		return try #require(unarchived).config
	}

	@Test("Every setting survives the envelope")
	func envelopeRoundTrips() throws {
		let config = sampleConfig()
		let restored = try roundTrip(config)

		#expect(restored == config)
	}

	@Test("A zero port means the sender left it out, not a port of zero")
	func absentPortsFallBackToTheDefault() throws {
		var config = ConnectionConfig()
		config.serverAddress = "irc.example.test"

		let restored = try roundTrip(config)

		#expect(restored.serverPort == ConnectionDefaults.serverPort)
		#expect(restored.proxyPort == ConnectionDefaults.proxyPort)
	}

	/// Out-of-range flood-control values used to trip a `precondition` in a
	/// setter that an XPC peer could reach.
	@Test("An out-of-range flood-control value is refused rather than fatal")
	func floodControlValuesAreClamped() {
		var config = ConnectionConfig()
		config.setFloodControl(delayInterval: 5, maximumMessages: 4)
		config.setFloodControl(delayInterval: 900, maximumMessages: 0)

		#expect(config.floodControlDelayInterval == 5)
		#expect(config.floodControlMaximumMessages == 4)
	}

	/// Decoding writes the two settings directly, so whatever the envelope
	/// carried reaches `repairDecodedValues` and is put back in range there.
	@Test(
		"A decoded flood-control value outside the supported range comes back as the default",
		arguments: [0, 900, UInt(Int.max) + 1, UInt.max] as [UInt]
	)
	func decodedFloodControlValuesOutsideTheRangeFallBackToTheDefault(_ stored: UInt) throws {
		/* A property list holds an unsigned 64-bit integer, so a crafted
		 envelope reaches the host with a message count no `Int` can name. The
		 dictionary is built and serialized directly because
		 `PropertyListValue.integer` carries an `Int` and could not express it. */
		let data = try PropertyListEncoder().encode(sampleConfig())
		let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
		var encoded = try #require(plist as? [String: Any])
		encoded["floodControlDelayInterval"] = NSNumber(value: UInt64(stored))
		encoded["floodControlMaximumMessages"] = NSNumber(value: UInt64(stored))
		let crafted = try PropertyListSerialization.data(
			fromPropertyList: encoded,
			format: .binary,
			options: 0
		)

		let config = try PropertyListDecoder().decode(ConnectionConfig.self, from: crafted)

		#expect(config.floodControlDelayInterval == ConnectionDefaults.floodControlDelayInterval)
		#expect(config.floodControlMaximumMessages == ConnectionDefaults.floodControlMaximumMessages)
		/* The host narrows the message count on every write, which is what an
		 unbounded decoded value would trap on. */
		#expect(Int(exactly: config.floodControlMaximumMessages) != nil)
	}

	// MARK: - Transport

	private func encodedSample(transport: Any?) throws -> Data {
		let data = try PropertyListEncoder().encode(sampleConfig())
		let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
		var encoded = try #require(plist as? [String: Any])
		encoded["transport"] = transport

		return try PropertyListSerialization.data(fromPropertyList: encoded, format: .binary, options: 0)
	}

	@Test("A WebSocket transport survives the envelope")
	func webSocketTransportRoundTrips() throws {
		var config = sampleConfig()
		config.transport = .webSocket(WebSocketTransportOptions(path: "/irc?token=a%20b", subprotocols: [.binary, .text]))

		#expect(try roundTrip(config) == config)
	}

	@Test("A configuration without a transport is a stream")
	func absentTransportIsAStream() throws {
		let config = try PropertyListDecoder().decode(ConnectionConfig.self, from: encodedSample(transport: nil))

		#expect(config.transport == .stream)
	}

	@Test(
		"A transport this build cannot read becomes a stream",
		arguments: ["a bare string", "an unknown kind", "a WebSocket with no options"]
	)
	func unreadableTransportIsAStream(_ shape: String) throws {
		let stored: Any = switch shape {
		case "a bare string": "webSocket"
		case "an unknown kind": ["kind": "carrierPigeon"]
		default: ["kind": "webSocket"]
		}
		let config = try PropertyListDecoder().decode(ConnectionConfig.self, from: encodedSample(transport: stored))

		#expect(config.transport == .stream)
		#expect(config.serverAddress == sampleConfig().serverAddress)
	}

	@Test(
		"A WebSocket path outside the rules is repaired to the root",
		arguments: [
			"",
			"irc",
			"/irc\r\nHost: evil",
			"/irc\n",
			"/irc\0",
			"/irc path",
			"/irc#fragment",
			"/irc%2",
			"/irc%zz",
			"/caf\u{E9}",
			"/" + String(repeating: "a", count: WebSocketTransportOptions.maximumPathLength),
		]
	)
	func invalidPathsAreRepaired(path: String) throws {
		let stored: [String: Any] = ["kind": "webSocket", "webSocket": ["path": path, "subprotocols": ["text.ircv3.net"]]]
		let config = try PropertyListDecoder().decode(ConnectionConfig.self, from: encodedSample(transport: stored))

		#expect(config.transport == .webSocket(WebSocketTransportOptions(path: "/", subprotocols: [.text])))
	}

	@Test(
		"A valid WebSocket path is kept as written",
		arguments: ["/", "/irc", "/irc?x=1", "/webirc/kiwiirc/?a=b&c=%20", "/" + String(repeating: "a", count: 1023)]
	)
	func validPathsAreKept(path: String) {
		#expect(WebSocketTransportOptions.isValidPath(path))
		#expect(WebSocketTransportOptions(path: path).repaired().path == path)
	}

	@Test("An empty or unknown subprotocol offer becomes both, text first, without duplicates")
	func subprotocolOfferIsRepaired() throws {
		for offer in [[], ["chat"], ["binary.ircv3.net", "binary.ircv3.net", "text.ircv3.net"]] {
			let stored: [String: Any] = ["kind": "webSocket", "webSocket": ["path": "/", "subprotocols": offer]]
			let config = try PropertyListDecoder().decode(ConnectionConfig.self, from: encodedSample(transport: stored))
			let expected: [WebSocketSubprotocol] = offer.count == 3 ? [.binary, .text] : [.text, .binary]

			#expect(config.transport == .webSocket(WebSocketTransportOptions(path: "/", subprotocols: expected)))
		}
	}

	@Test(
		"A zero port becomes the transport's default",
		arguments: [
			(ConnectionTransport.stream, false, ConnectionDefaults.serverPort),
			(.webSocket(WebSocketTransportOptions()), false, ConnectionDefaults.webSocketPort),
			(.webSocket(WebSocketTransportOptions()), true, ConnectionDefaults.webSocketPortSecure),
		]
	)
	func zeroPortGetsTheTransportDefault(transport: ConnectionTransport, secure: Bool, expected: UInt16) throws {
		var config = ConnectionConfig()
		config.serverAddress = "irc.example.test"
		config.serverPort = 0
		config.connectionPrefersSecuredConnection = secure
		config.transport = transport

		#expect(try roundTrip(config).serverPort == expected)
	}

	@Test("A proxy type this build does not know becomes no proxy")
	func unsupportedProxyTypeIsRefused() throws {
		let data = try PropertyListEncoder().encode(sampleConfig())
		let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
		var encoded = try #require([String: PropertyListValue](propertyList: plist))
		encoded["proxyType"] = 4

		let config = try #require(PropertyListModel.decode(ConnectionConfig.self, from: encoded))

		#expect(config.proxyType == .none)
	}
}
