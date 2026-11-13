// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@Suite("WebSocket session wiring")
@MainActor
struct WebSocketSessionTests {
	private func session(
		_ endpoint: ServerEndpoint,
		policies: STSPolicyStore = STSPolicyStore(userDefaults: nil),
		primaryEncoding: String.Encoding = .utf8
	) -> ServerSession {
		var config = ServerConfig()
		config.serverList = [endpoint]
		config.primaryEncoding = primaryEncoding.rawValue
		return ServerSession(
			config: config,
			environment: ChatEnvironment(settings: .current(), services: ChatServices(stsPolicies: policies))
		)
	}

	private func webSocketEndpoint(secured: Bool, port: UInt16) -> ServerEndpoint {
		ServerEndpoint(
			serverAddress: "irc.example.net",
			serverPort: port,
			prefersSecuredConnection: secured,
			transport: .webSocket,
			webSocketPath: "/irc"
		)
	}

	@Test("A WebSocket entry dials a WebSocket with its path, text first for UTF-8")
	func webSocketEndpointIsMapped() throws {
		let connection = try #require(session(webSocketEndpoint(secured: true, port: 443)).takeConnectionEndpoint())
		#expect(connection.transport == .webSocket(WebSocketTransportOptions(path: "/irc", subprotocols: [.text, .binary])))
		#expect(connection.serverPort == 443)
		#expect(connection.connectionPrefersSecuredConnection)
		#expect(connection.connectionRequiresTrustedCertificate == false)
	}

	@Test("A session in another encoding asks for binary frames first")
	func latinPrefersBinary() throws {
		let connection = try #require(
			session(webSocketEndpoint(secured: false, port: 80), primaryEncoding: .isoLatin1).takeConnectionEndpoint()
		)
		#expect(connection.transport == .webSocket(WebSocketTransportOptions(path: "/irc", subprotocols: [.binary, .text])))
	}

	@Test("An IRC entry stays a stream")
	func ircEndpointIsStream() throws {
		let connection = try #require(
			session(ServerEndpoint(serverAddress: "irc.example.net", serverPort: 6697)).takeConnectionEndpoint()
		)
		#expect(connection.transport == .stream)
	}

	@Test("A stored STS policy moves a plain WebSocket to IRC over TLS on the policy port")
	func stsMovesPlainWebSocketToTLS() throws {
		let policies = STSPolicyStore(userDefaults: nil)
		policies.setPolicy(STSPolicy(port: 6697, expiresAt: .distantFuture, preload: false), forHost: "irc.example.net")
		let connection = try #require(
			session(webSocketEndpoint(secured: false, port: 80), policies: policies).takeConnectionEndpoint()
		)
		#expect(connection.transport == .stream)
		#expect(connection.serverPort == 6697)
		#expect(connection.connectionPrefersSecuredConnection)
		#expect(connection.connectionRequiresTrustedCertificate)
	}

	@Test("A stored STS policy keeps a secure WebSocket and requires a trusted certificate")
	func stsKeepsSecureWebSocket() throws {
		let policies = STSPolicyStore(userDefaults: nil)
		policies.setPolicy(STSPolicy(port: 6697, expiresAt: .distantFuture, preload: false), forHost: "irc.example.net")
		let connection = try #require(
			session(webSocketEndpoint(secured: true, port: 443), policies: policies).takeConnectionEndpoint()
		)
		guard case .webSocket = connection.transport else {
			Issue.record("Expected a WebSocket transport")
			return
		}
		#expect(connection.serverPort == 443)
		#expect(connection.connectionRequiresTrustedCertificate)
	}

	@Test("/conn keeps the WebSocket transport on its default port")
	func connCommandKeepsTransport() {
		let endpoint = session(webSocketEndpoint(secured: true, port: 8443)).connectCommandEndpoint(host: "other.example.net")
		#expect(endpoint.transport == .webSocket)
		#expect(endpoint.port == 443)
		#expect(endpoint.webSocketPath == "/irc")
	}

	@Test("Text and unnegotiated framing force UTF-8; binary keeps the configured encoding", arguments: [
		(String?("text.ircv3.net"), true),
		(String?("binary.ircv3.net"), false),
		(String?.none, true),
		(String?("unknown.example"), true),
	])
	func framingDecidesUTF8(name: String?, requiresUTF8: Bool) {
		#expect(WebSocketFraming(subprotocolName: name).requiresUTF8 == requiresUTF8)
	}

	@Test("A text subprotocol makes a Latin-1 session encode UTF-8")
	func negotiatedTextForcesUTF8() async throws {
		let session = TestServerSession()
		session.config.primaryEncoding = String.Encoding.isoLatin1.rawValue
		session.setConnectionTransportForTesting(.connected)
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		#expect(session.effectivePrimaryEncoding == .isoLatin1)
		connection.callbackReceiver.didNegotiateWebSocketSubprotocol("text.ircv3.net")
		try await Eventually.until("the negotiation to arrive") { connection.webSocketFraming != nil }
		#expect(session.effectivePrimaryEncoding == .utf8)
	}

	@Test("An import with an invalid WebSocket path is refused with its own message")
	func importRefusesInvalidPath() {
		let dictionary: [String: PropertyListValue] = [
			"uniqueIdentifier": .string("S"),
			"serverList": .array([.dictionary([
				"uniqueIdentifier": .string("A"),
				"serverAddress": .string("irc.example.net"),
				"transport": .string("websocket"),
				"webSocketPath": .string("/a b"),
			])]),
		]
		#expect {
			try SettingsSessionArchive.decode(.array([.dictionary(dictionary)]))
		} throws: { error in
			guard case SettingsTransferError.invalidWebSocketPath = error else { return false }
			return true
		}
	}

	@Test("An exported WebSocket server imports unchanged")
	func importRoundTrip() throws {
		var config = ServerConfig()
		config.serverList = [webSocketEndpoint(secured: true, port: 443)]
		let imported = try SettingsSessionArchive.decode(.array([.dictionary(config.dictionaryValue)]))
		#expect(imported.first?.serverList.first?.webSocketURL == "wss://irc.example.net:443/irc")
	}
}

@Suite("WebSocket /conn paths")
@MainActor
struct WebSocketConnCommandTests {
	@Test("/conn to an unconfigured host drops the current path's query")
	func unconfiguredHostLosesQuery() {
		var config = ServerConfig()
		config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.net", serverPort: 443, prefersSecuredConnection: true,
			transport: .webSocket, webSocketPath: "/irc?token=secret"
		)]
		let session = ServerSession(
			config: config,
			environment: ChatEnvironment(settings: .current(), services: ChatServices(stsPolicies: STSPolicyStore(userDefaults: nil)))
		)
		#expect(session.connectCommandEndpoint(host: "other.example.net").webSocketPath == "/irc")
		#expect(session.connectCommandEndpoint(host: "IRC.example.net").webSocketPath == "/irc?token=secret")
	}
}
