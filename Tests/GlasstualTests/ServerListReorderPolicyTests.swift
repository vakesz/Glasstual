/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Server-list reordering")
struct ServerListReorderPolicyTests {
	@Test("Moving down accounts for removal from the original position")
	func downwardDestinationIndex() {
		#expect(ServerListReorderPolicy.destinationIndex(proposed: 4, movingFrom: 1) == 3)
		#expect(ServerListReorderPolicy.destinationIndex(proposed: 1, movingFrom: 4) == 1)
	}

	@Test("Channels cannot cross server or channel-query boundaries")
	func channelMoveBoundaries() {
		#expect(
			ServerListReorderPolicy.permitsChannelMove(
				sharesClient: true,
				draggedIsChannel: true,
				destinationIsChannel: true
			)
		)
		#expect(
			ServerListReorderPolicy.permitsChannelMove(
				sharesClient: false,
				draggedIsChannel: true,
				destinationIsChannel: true
			) == false
		)
		#expect(
			ServerListReorderPolicy.permitsChannelMove(
				sharesClient: true,
				draggedIsChannel: true,
				destinationIsChannel: false
			) == false
		)
	}
}
