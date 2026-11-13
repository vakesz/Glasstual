// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@Suite("Server transport")
struct ServerTransportTests {
	@Test("Each transport defaults to its own ports", arguments: [
		(ServerTransport.irc, false, UInt16(6667)),
		(.irc, true, 6697),
		(.webSocket, false, 80),
		(.webSocket, true, 443),
	])
	func defaultPorts(transport: ServerTransport, secured: Bool, port: UInt16) {
		#expect(transport.defaultPort(secured: secured) == port)
	}

	@Test("An entry stored before there was a transport decodes as IRC")
	func legacyEntryDecodesAsIRC() throws {
		let stored: [String: PropertyListValue] = [
			"uniqueIdentifier": .string("A"),
			"serverAddress": .string("irc.example.net"),
			"serverPort": .integer(6697),
			"prefersSecuredConnection": .boolean(true),
		]
		let endpoint = try #require(PropertyListModel.decode(ServerEndpoint.self, from: stored))
		#expect(endpoint.transport == .irc)
		#expect(endpoint.webSocketPath == "/")
	}

	@Test("An IRC entry encodes exactly the keys it always had")
	func ircEntryEncodesUnchanged() {
		let endpoint = ServerEndpoint(uniqueIdentifier: "A", serverAddress: "irc.example.net", serverPort: 6667)
		let encoded = PropertyListModel.encode(endpoint)
		#expect(Set(encoded.keys) == ["uniqueIdentifier", "serverAddress", "serverPort", "prefersSecuredConnection"])
	}

	@Test("A WebSocket entry round-trips its transport and path")
	func webSocketRoundTrip() throws {
		let endpoint = ServerEndpoint(
			uniqueIdentifier: "A",
			serverAddress: "irc.example.net",
			serverPort: 8443,
			prefersSecuredConnection: true,
			transport: .webSocket,
			webSocketPath: "/irc?x=1"
		)
		let encoded = PropertyListModel.encode(endpoint)
		#expect(encoded["transport"] == .string("websocket"))
		let decoded = try #require(PropertyListModel.decode(ServerEndpoint.self, from: encoded))
		#expect(decoded == endpoint)
		#expect(decoded.webSocketURL == "wss://irc.example.net:8443/irc?x=1")
	}

	@Test("An unknown transport decodes as IRC and an invalid path as the root")
	func unknownValuesAreRepaired() throws {
		let stored: [String: PropertyListValue] = [
			"uniqueIdentifier": .string("A"),
			"serverAddress": .string("irc.example.net"),
			"transport": .string("carrier-pigeon"),
			"webSocketPath": .string("no-slash"),
		]
		let endpoint = try #require(PropertyListModel.decode(ServerEndpoint.self, from: stored))
		#expect(endpoint.transport == .irc)
		#expect(endpoint.webSocketPath == "/")
	}

	@Test("Paths follow the one request-target rule", arguments: [
		("/", true),
		("/irc", true),
		("/irc?token=a%20b", true),
		("", false),
		("irc", false),
		("/a b", false),
		("/a\r\nHost: x", false),
		("/a#frag", false),
		("/%zz", false),
		("/" + String(repeating: "a", count: 1024), false),
	])
	func pathRule(path: String, valid: Bool) {
		#expect(ServerTransport.isValidWebSocketPath(path) == valid)
	}

	@Test("WebSocket URLs parse into an entry's fields")
	func urlParsing() throws {
		let secure = try #require(WebSocketAddress("wss://IRC.Example.net/gateway?a=1#chat,other"))
		#expect(secure.host == "irc.example.net")
		#expect(secure.port == 443)
		#expect(secure.secured)
		#expect(secure.path == "/gateway?a=1")
		#expect(secure.fragmentChannelList == "#chat,#other")

		let plain = try #require(WebSocketAddress("ws://irc.example.net"))
		#expect(plain.port == 80)
		#expect(plain.path == "/")
		#expect(plain.secured == false)

		let literal = try #require(WebSocketAddress("wss://[::1]:8443/x"))
		#expect(literal.host == "::1")
		#expect(literal.port == 8443)
		#expect(WebSocketAddress.url(host: literal.host, port: literal.port, secured: true, path: literal.path)
			== "wss://[::1]:8443/x")
	}

	@Test("URLs a server entry cannot hold are refused", arguments: [
		"wss://user:secret@irc.example.net/",
		"irc://irc.example.net/",
		"https://irc.example.net/",
		"wss:///path",
		"wss://irc.example.net/a b",
	])
	func urlRefusals(location: String) {
		#expect(WebSocketAddress(location) == nil)
	}

	@Test("The console URL hides query values")
	func displayURLMasksQuery() {
		let shown = WebSocketAddress.displayURL(
			host: "irc.example.net", port: 443, secured: true, path: "/irc?token=s3cret&bare"
		)
		#expect(shown == "wss://irc.example.net:443/irc?token=…&…")
		#expect(shown.contains("s3cret") == false)
	}

	@Test("Catalog entries carry a transport and alternate servers")
	func networkCatalogTransport() throws {
		let network = try #require(Network(dictionary: [
			"name": .string("Example"),
			"serverAddress": .string("irc.example.net"),
			"prefersSecuredConnection": .boolean(true),
			"alternateServers": .array([
				.dictionary([
					"serverAddress": .string("ws.example.net"),
					"prefersSecuredConnection": .boolean(true),
					"transport": .string("websocket"),
					"webSocketPath": .string("/irc"),
				]),
				.dictionary([
					"serverAddress": .string("bad.example.net"),
					"transport": .string("websocket"),
					"webSocketPath": .string("no-slash"),
				]),
			]),
		]))
		#expect(network.transport == .irc)
		#expect(network.serverPort == 6697)
		#expect(network.alternateEndpoints.count == 1)
		let servers = network.serverList
		#expect(servers.count == 2)
		#expect(servers[1].webSocketURL == "wss://ws.example.net:443/irc")
		#expect(Set(servers.map(\.uniqueIdentifier)).count == 2)
	}
}

@Suite("Connection requests for WebSocket URLs")
struct ServerConnectionRequestWebSocketTests {
	private let options = ServerConnectionOptions(
		connectWhenCreated: true,
		mergeConnectionIfPossible: false,
		selectFirstChannelAdded: false
	)

	@Test("/server takes a wss URL with its path and fragment channels")
	func secureURL() throws {
		let request = try #require(ServerConnectionRequest.parse(
			"wss://irc.example.net/irc#a,b", channels: nil, options: options
		))
		#expect(request.transport == .webSocket)
		#expect(request.serverPort == 443)
		#expect(request.connectSecurely)
		#expect(request.webSocketPath == "/irc")
		#expect(request.channels == ["#a", "#b"])
	}

	@Test("-TLS makes a ws URL secure and moves it to the secure default port")
	func tlsFlagUpgrades() throws {
		let request = try #require(ServerConnectionRequest.parse(
			"-TLS ws://irc.example.net/ secret", channels: nil, options: options
		))
		#expect(request.connectSecurely)
		#expect(request.serverPort == 443)
		#expect(request.serverPassword == "secret")
	}

	@Test("An explicit port is kept")
	func explicitPort() throws {
		let request = try #require(ServerConnectionRequest.parse(
			"ws://irc.example.net:8080/irc", channels: nil, options: options
		))
		#expect(request.serverPort == 8080)
		#expect(request.connectSecurely == false)
	}

	@Test("Plain host arguments are still IRC")
	func plainHostIsIRC() throws {
		let request = try #require(ServerConnectionRequest.parse("irc.example.net +6697", channels: nil, options: options))
		#expect(request.transport == .irc)
	}

	@Test("The system never hands the app a WebSocket link", arguments: [
		"ws://irc.example.net/#chat", "wss://irc.example.net/irc",
	])
	func externalLinksRefused(location: String) {
		#expect(ApplicationLink.parse(location) == nil)
	}
}
