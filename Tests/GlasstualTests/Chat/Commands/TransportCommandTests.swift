// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@Suite("/transport")
@MainActor
struct TransportCommandTests {
	@Test("The command reads its three forms and refuses the rest", arguments: [
		("", TransportCommandRequest?.some(.show)),
		("irc", .set(.irc, path: nil)),
		("WebSocket", .set(.webSocket, path: nil)),
		("websocket /irc", .set(.webSocket, path: "/irc")),
		("irc /path", nil),
		("websocket /a extra", nil),
		("carrier", nil),
	])
	func parsing(arguments: String, expected: TransportCommandRequest?) {
		#expect(TransportCommandRequest(CommandArguments(arguments)) == expected)
	}

	private func session() -> TestServerSession {
		let session = TestServerSession()
		session.config.serverList = [ServerEndpoint(serverAddress: "irc.example.net", serverPort: 6697, prefersSecuredConnection: true)]
		return session
	}

	@Test("Switching to WebSocket moves a default port and stores the path")
	func switchesToWebSocket() {
		let session = session()
		session.sendCommand("TRANSPORT websocket /gateway", completeTarget: false, target: nil)
		let server = session.config.serverList[0]
		#expect(server.transport == .webSocket)
		#expect(server.serverPort == 443)
		#expect(server.webSocketPath == "/gateway")
		#expect(session.sentLines.count == 0)
	}

	@Test("Switching back keeps a port the person chose")
	func keepsChosenPort() {
		let session = session()
		session.config.serverList[0].serverPort = 7000
		session.sendCommand("TRANSPORT websocket", completeTarget: false, target: nil)
		session.sendCommand("TRANSPORT irc", completeTarget: false, target: nil)
		#expect(session.config.serverList[0].serverPort == 7000)
		#expect(session.config.serverList[0].transport == .irc)
	}

	@Test("An invalid path changes nothing")
	func invalidPathRefused() {
		let session = session()
		session.sendCommand("TRANSPORT websocket no-slash", completeTarget: false, target: nil)
		#expect(session.config.serverList[0].transport == .irc)
	}
}

@Suite("Server properties transport fields")
@MainActor
struct ServerPropertiesTransportTests {
	private func model(port: UInt16 = 6697, secured: Bool = true) -> ServerPropertiesModel {
		var config = ServerConfig(connectionName: "Example")
		config.serverList = [ServerEndpoint(serverAddress: "irc.example.net", serverPort: port, prefersSecuredConnection: secured)]
		return ServerPropertiesModel(config: config, networkList: NetworkList(networks: []))
	}

	@Test("A default port follows the transport and the security switch", arguments: [
		(UInt16(6697), true, ServerTransport.webSocket, "443"),
		(6667, false, .webSocket, "80"),
		(7000, true, .webSocket, "7000"),
	])
	func defaultPortFollows(port: UInt16, secured: Bool, transport: ServerTransport, expected: String) {
		let model = model(port: port, secured: secured)
		model.primaryServerTransport = transport
		#expect(model.serverPort == expected)
	}

	@Test("Securing a WebSocket moves 80 to 443")
	func securingWebSocket() {
		let model = model(port: 6667, secured: false)
		model.primaryServerTransport = .webSocket
		model.primaryServerIsSecured = true
		#expect(model.serverPort == "443")
	}

	@Test("A pasted wss URL fills the transport, port, security and path")
	func pastedURL() {
		let model = model(port: 6667, secured: false)
		model.serverAddress = "wss://gateway.example.net:8443/irc"
		model.serverAddressTextDidChange()
		#expect(model.serverAddress == "gateway.example.net")
		#expect(model.serverPort == "8443")
		#expect(model.primaryServerIsSecured)
		#expect(model.primaryServerTransport == .webSocket)
		#expect(model.primaryWebSocketPath == "/irc")
		#expect(model.submittedConfig()?.serverList.first?.webSocketURL == "wss://gateway.example.net:8443/irc")
	}

	@Test("An invalid path stops the sheet saving")
	func invalidPathBlocksSave() {
		let model = model()
		model.primaryServerTransport = .webSocket
		model.primaryWebSocketPath = "irc"
		#expect(model.validationFault?.selection == .general)
	}

	@Test("Endpoint rows keep their transport and refuse a bad path")
	func endpointRows() {
		let list = ServerEndpointListModel()
		list.replace(with: [ServerEndpoint(serverAddress: "irc.example.net", serverPort: 6697, prefersSecuredConnection: true)])
		let id = list.entries[0].id
		list.setTransport(.webSocket, for: id)
		#expect(list.entries[0].port == "443")
		list.webSocketPath(for: id).wrappedValue = "bad"
		#expect(list.validatedServers() == nil)
		#expect(list.faults == [.webSocketPath])
		list.webSocketPath(for: id).wrappedValue = "/ok"
		#expect(list.validatedServers()?.first?.webSocketURL == "wss://irc.example.net:443/ok")
	}
}
