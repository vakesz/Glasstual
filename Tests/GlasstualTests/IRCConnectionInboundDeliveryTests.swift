/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Inbound connection delivery")
@MainActor
struct IRCConnectionInboundDeliveryTests {
	private func connectedClient() -> (GLTTestClient, Connection) {
		let client = GLTTestClient()
		client.isConnected = true
		let connection = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = connection
		return (client, connection)
	}

	/// The connection drains the host's callbacks through one ordered stream, so
	/// the client answers the lines in the order the server sent them.
	@Test("Lines are answered in the order the connection delivered them")
	func answersInWireOrder() {
		let (client, connection) = connectedClient()

		for token in ["one", "two", "three"] {
			client.ircConnection(connection, didReceiveData: "PING :\(token)")
		}

		#expect(client.sentLines as? [String] == ["PONG one", "PONG two", "PONG three"])
	}

	/// A reconnect replaces the socket. Lines that were already in flight on the
	/// retired connection must not act on the new session.
	@Test("A line from a connection the client no longer owns is dropped")
	func ignoresRetiredConnection() {
		let (client, _) = connectedClient()
		let retired = Connection(config: IRCConnectionConfig(), onClient: client)

		client.ircConnection(retired, didReceiveData: "PING :stale")

		#expect(client.sentLines.count == 0)
	}

	@Test("Empty data is not treated as a line")
	func ignoresEmptyData() {
		let (client, connection) = connectedClient()

		client.ircConnection(connection, didReceiveData: "")

		#expect(client.sentLines.count == 0)
	}
}
