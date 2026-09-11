/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/// What the sidebar lists, and what the commands that move the selection
/// address. They are not the same list, which is the point of most of these.
@MainActor
@Suite("Server list projection")
struct ServerListProjectionTests {
	private let list = ServerList()
	private let alpha: GLTTestClient
	private let beta: GLTTestClient
	private let alphaChannels: [IRCChannel]
	private let betaChannels: [IRCChannel]

	init() {
		/* Locals first: a closure over a stored property would capture `self`
		 before every property is initialised, which the compiler refuses. */
		let alpha = GLTTestClient()
		let beta = GLTTestClient()
		alpha.config.connectionName = "Alpha"
		beta.config.connectionName = "Beta"
		let alphaChannels = ["#swift", "#coffee"].map { Self.channel(named: $0, on: alpha) }
		let betaChannels = [Self.channel(named: "#swiftui", on: beta)]
		alpha.channelList = alphaChannels
		beta.channelList = betaChannels
		alpha.sidebarItemIsExpanded = true
		beta.sidebarItemIsExpanded = false
		self.alpha = alpha
		self.beta = beta
		self.alphaChannels = alphaChannels
		self.betaChannels = betaChannels
		let clients: [IRCClient] = [alpha, beta]
		list.clientSource = { clients }
		list.filterText = ""
	}

	private static func channel(named name: String, on client: IRCClient) -> IRCChannel {
		let channel = IRCChannel(config: ChannelConfig(channelName: name))
		channel.associatedClient = client
		return channel
	}

	@Test("Every conversation is listed, and disclosure decides what is drawn")
	func rowsCarryTheWholeTree() throws {
		#expect(list.rows.map(\.title) == ["Alpha", "Beta"])
		let alphaRow = try #require(list.rows.first)
		let betaRow = try #require(list.rows.last)
		#expect(alphaRow.channels.map(\.title) == ["#swift", "#coffee"])
		#expect(alphaRow.isExpanded)
		#expect(alphaRow.showsDisclosure)
		/* A collapsed server keeps its conversations in the row so that the
		 outline has something to disclose; the chevron would otherwise vanish
		 the moment it was used. */
		#expect(betaRow.channels.map(\.title) == ["#swiftui"])
		#expect(betaRow.isExpanded == false)
		#expect(betaRow.showsDisclosure)
	}

	@Test("A server with no conversations is offered no disclosure")
	func serverWithoutChannelsHasNoChevron() throws {
		beta.channelList = []
		list.filterText = ""

		#expect(try #require(list.rows.last).showsDisclosure == false)
	}

	@Test("The filter narrows what is listed and discloses the matches")
	func filterNarrowsTheListedRows() throws {
		list.filterText = "coffee"

		#expect(list.rows.map(\.title) == ["Alpha"])
		#expect(try #require(list.rows.first).channels.map(\.title) == ["#coffee"])
		#expect(list.hasNoFilterMatches == false)

		list.filterText = "swift"

		#expect(list.rows.map(\.title) == ["Alpha", "Beta"])
		/* Beta is collapsed, and its match is still drawn: while a filter says
		 what is on screen, disclosure does not. */
		#expect(try #require(list.rows.last).isExpanded)
	}

	@Test("A filter that matches nothing is a no-results state, not an empty sidebar")
	func filterWithoutMatchesReportsNoResults() {
		list.filterText = "nothing-matches-this"

		#expect(list.rows.isEmpty)
		#expect(list.hasNoFilterMatches)
	}

	/// The regression: the filter used to narrow the index space every
	/// selection command shares, so typing in the search field moved the
	/// selection off the conversation the reader was in.
	@Test("The filter does not narrow the index space the selection commands use")
	func filterLeavesTheSelectableItemsAlone() throws {
		let openChannel = try #require(alphaChannels.last)
		let rowBeforeFiltering = list.row(forItem: openChannel)
		#expect(rowBeforeFiltering >= 0)

		list.filterText = "nothing-matches-this"

		#expect(list.numberOfRows == 4)
		#expect(list.row(forItem: openChannel) == rowBeforeFiltering)
		#expect(list.item(atRow: rowBeforeFiltering) as? IRCChannel === openChannel)
	}

	/** The other half of the same rule: a filter draws the matches under a
	 closed server, and a row that is drawn is a row the reader can click.

	 Leaving them out of the index space answered a click on one with
	 `selectedRow == -1`, and ⌥↑/⌥↓ then walked from a row that was not in the
	 list at all. */
	@Test("A filtered match under a closed server is selectable where it is drawn")
	func filteredMatchesUnderClosedServersAreSelectable() throws {
		let hidden = try #require(betaChannels.first)
		#expect(list.row(forItem: hidden) == -1)

		list.filterText = "swiftui"

		/* Beta is still collapsed, and the filter is drawing its match. */
		#expect(list.isExpanded(beta) == false)
		#expect(try #require(list.rows.last).channels.map(\.title) == ["#swiftui"])
		let row = list.row(forItem: hidden)
		#expect(row >= 0)
		#expect(list.item(atRow: row) as? IRCChannel === hidden)

		list.selectItem(at: row)
		#expect(list.selectedRow == row)
	}

	@Test("A collapsed server's conversations have no row to move onto")
	func collapsedConversationsAreNotSelectable() throws {
		let hidden = try #require(betaChannels.first)
		#expect(list.row(forItem: hidden) == -1)

		beta.sidebarItemIsExpanded = true

		#expect(list.row(forItem: hidden) == 4)
		#expect(list.numberOfRows == 5)
	}

	/// A row is compared by what it draws, so the badge colour has to be part
	/// of the row: read inside the row body it changed nothing SwiftUI could
	/// see, and the badges kept the colour they were first drawn with.
	@Test("The unread badge colour travels in the row")
	func unreadBadgeColourIsPartOfTheRow() throws {
		let key = Preferences.Badges.serverListUnreadHighlight
		let previous = key.storedValue
		defer {
			key.storedValue = previous
			list.filterText = ""
		}

		key.storedValue = PreferenceColor(NSColor(srgbRed: 0.9, green: 0.2, blue: 0.1, alpha: 1))
		list.filterText = ""
		let tinted = try #require(list.rows.first?.channels.first)
		#expect(tinted.unreadBadgeTint != nil)

		key.storedValue = nil
		list.filterText = ""
		let untinted = try #require(list.rows.first?.channels.first)
		#expect(untinted.unreadBadgeTint == nil)
		#expect(tinted != untinted)
	}
}
