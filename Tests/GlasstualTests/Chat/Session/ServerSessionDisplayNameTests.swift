// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// One connection has one name: the sidebar's, wherever else it is shown.
@Suite("Server session display name")
struct ServerSessionDisplayNameTests {
	@Test("The reader's name for a connection wins over the one the server announces")
	func connectionNameWins() {
		#expect(ServerSession.displayName(
			connectionName: "Example Network", announcedNetworkName: "Example IRC Network"
		) == "Example Network")
		#expect(ServerSession.displayName(connectionName: "Example Network", announcedNetworkName: nil) == "Example Network")
	}

	@Test("A connection without a name is shown under the announced one")
	func announcedNameStandsIn() {
		#expect(ServerSession.displayName(connectionName: " ", announcedNetworkName: "Example IRC Network")
			== "Example IRC Network")
		#expect(ServerSession.displayName(connectionName: "", announcedNetworkName: nil).isEmpty)
	}

	@MainActor
	@Test("A session keeps the sidebar's name once the server has announced its own")
	func sessionKeepsTheSidebarName() {
		let session = ServerSession(config: ServerConfig(connectionName: "Example Network"))
		_ = session.supportInfo.processConfigurationData("NETWORK=Example :are supported by this server")
		#expect(session.networkName != nil)
		#expect(session.networkNameAlt == session.name)
	}
}
