/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Channel list sort ordering")
struct MenuChannelOrderingTests {
	private func makeChannel(named name: String, isQuery: Bool) -> IRCChannel {
		Channel(
			config: ChannelConfig(channelName: name, type: isQuery ? .privateMessage : .channel)
		)
	}

	@Test("Channels sort before queries in both directions")
	func isStrictWeakOrdering() {
		let channel = makeChannel(named: "#zulu", isQuery: false)
		let query = makeChannel(named: "alpha", isQuery: true)

		#expect(MenuWindowPolicy.channelsOrderedBeforeQueries(channel, query))
		// The reverse must answer false. Reporting "unordered" both ways is
		// not a strict weak ordering and lets sort(by:) misbehave.
		#expect(MenuWindowPolicy.channelsOrderedBeforeQueries(query, channel) == false)
	}

	@Test("Items of the same kind sort case-insensitively by name")
	func sortsByNameWithinKind() {
		let first = makeChannel(named: "#Alpha", isQuery: false)
		let second = makeChannel(named: "#beta", isQuery: false)

		#expect(MenuWindowPolicy.channelsOrderedBeforeQueries(first, second))
		#expect(MenuWindowPolicy.channelsOrderedBeforeQueries(second, first) == false)
	}

	@Test("Sorting a mixed list puts every channel ahead of every query")
	func sortsMixedList() {
		let items = [
			makeChannel(named: "zoe", isQuery: true),
			makeChannel(named: "#beta", isQuery: false),
			makeChannel(named: "adam", isQuery: true),
			makeChannel(named: "#alpha", isQuery: false),
		]

		let sorted = items.sorted(by: MenuWindowPolicy.channelsOrderedBeforeQueries)

		#expect(sorted.map(\.name) == ["#alpha", "#beta", "adam", "zoe"])
	}

	@Test("An item never sorts before itself")
	func isIrreflexive() {
		let channel = makeChannel(named: "#chat", isQuery: false)

		#expect(MenuWindowPolicy.channelsOrderedBeforeQueries(channel, channel) == false)
	}
}
