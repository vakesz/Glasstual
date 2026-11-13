// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// Networks of a bouncer account are drawn under it, ordered and selected as
/// part of the same list.
@MainActor
@Suite("Sidebar bouncer nesting", .serialized)
struct SidebarBouncerNestingTests {
	private final class Fixture {
		let model = Sidebar()
		let chat = ChatSession()
		let account = TestServerSession()
		let libera = TestServerSession()
		let oftc = TestServerSession()
		let plain = TestServerSession()
		let accountChannel: Conversation
		let liberaChannel: Conversation
		let oftcChannel: Conversation

		init() {
			account.config.connectionName = "Account"
			libera.config.connectionName = "Libera"
			oftc.config.connectionName = "OFTC"
			plain.config.connectionName = "Plain"
			for (session, network) in [(libera, "1"), (oftc, "2")] {
				session.config.bouncerNetwork = BouncerNetworkBinding(
					parentIdentifier: account.uniqueIdentifier, networkIdentifier: network
				)
			}
			accountChannel = Self.channel("#account", on: account)
			liberaChannel = Self.channel("#swift", on: libera)
			oftcChannel = Self.channel("#kernel", on: oftc)
			for session in [account, libera, oftc, plain] {
				session.sidebarItemIsExpanded = true
			}
			// Saved order has the networks apart from their account.
			chat.sessions = [account, plain, libera, oftc]
			let chat = chat
			model.chatSessionSource = { chat }
			refresh()
		}

		private static func channel(_ name: String, on session: ServerSession) -> Conversation {
			let channel = Conversation(config: ConversationConfig(name: name))
			channel.associatedSession = session
			session.conversationList = [channel]
			return channel
		}

		func refresh() {
			model.filterText = model.filterText
		}
	}

	@Test("Networks are drawn inside their account, which stays in its own place among the roots")
	func networksNestUnderTheirAccount() throws {
		let fixture = Fixture()

		#expect(fixture.model.rows.map(\.title) == ["Account", "Plain"])
		let account = try #require(fixture.model.rows.first)
		#expect(account.networks.map(\.title) == ["Libera", "OFTC"])
		#expect(account.conversations.map(\.title) == ["#account"])
		#expect(account.networks.first?.conversations.map(\.title) == ["#swift"])
		#expect(account.showsDisclosure)
		#expect(fixture.model.rows.last?.networks.isEmpty == true)
	}

	@Test("Selection and navigation walk an account, its channels, then each network in turn")
	func selectableOrderIsDrawingOrder() {
		let fixture = Fixture()

		let order = fixture.model.selectableItems
		#expect(order.map(\.uniqueIdentifier) == [
			fixture.account.uniqueIdentifier, fixture.accountChannel.uniqueIdentifier,
			fixture.libera.uniqueIdentifier, fixture.liberaChannel.uniqueIdentifier,
			fixture.oftc.uniqueIdentifier, fixture.oftcChannel.uniqueIdentifier,
			fixture.plain.uniqueIdentifier,
		])
		#expect(fixture.model.groupItems.map(\.uniqueIdentifier) == [
			fixture.account.uniqueIdentifier, fixture.libera.uniqueIdentifier,
			fixture.oftc.uniqueIdentifier, fixture.plain.uniqueIdentifier,
		])
	}

	@Test("A collapsed account takes its networks out of the walk, unless one of them is selected")
	func collapsedAccountHidesItsNetworks() {
		let fixture = Fixture()
		fixture.account.sidebarItemIsExpanded = false
		fixture.refresh()

		let identifiers = Set(fixture.model.selectableItems.map(\.uniqueIdentifier))
		#expect(identifiers.contains(fixture.account.uniqueIdentifier))
		#expect(identifiers.contains(fixture.libera.uniqueIdentifier) == false)
		#expect(identifiers.contains(fixture.liberaChannel.uniqueIdentifier) == false)

		fixture.model.select(fixture.libera)
		#expect(fixture.model.selectedItem == nil)
	}

	@Test("A collapsed network hides only its own channels")
	func collapsedNetworkHidesItsChannels() {
		let fixture = Fixture()
		fixture.libera.sidebarItemIsExpanded = false
		fixture.refresh()

		let identifiers = Set(fixture.model.selectableItems.map(\.uniqueIdentifier))
		#expect(identifiers.contains(fixture.libera.uniqueIdentifier))
		#expect(identifiers.contains(fixture.liberaChannel.uniqueIdentifier) == false)
		#expect(identifiers.contains(fixture.oftcChannel.uniqueIdentifier))
	}

	@Test("A hidden account hands its networks to the top level and leaves the walk")
	func hiddenAccountPromotesItsNetworks() {
		let fixture = Fixture()
		fixture.account.config.bouncerHidesParent = true
		fixture.refresh()

		#expect(fixture.model.rows.map(\.title) == ["Libera", "OFTC", "Plain"])
		let identifiers = fixture.model.selectableItems.map(\.uniqueIdentifier)
		#expect(identifiers.contains(fixture.account.uniqueIdentifier) == false)
		#expect(identifiers.contains(fixture.accountChannel.uniqueIdentifier) == false)
		#expect(identifiers.contains(fixture.libera.uniqueIdentifier))
	}

	@Test("An account with nothing under it is never hidden")
	func accountWithoutNetworksStaysVisible() {
		let fixture = Fixture()
		fixture.plain.config.bouncerHidesParent = true
		fixture.refresh()

		#expect(fixture.model.rows.map(\.title).contains("Plain"))
	}

	@Test("A favourite channel of a hidden account is still listed under Favorites")
	func hiddenAccountKeepsItsFavorites() {
		let fixture = Fixture()
		var channelConfig = fixture.accountChannel.config
		channelConfig.isFavorite = true
		fixture.accountChannel.updateConfig(channelConfig)
		fixture.account.config.bouncerHidesParent = true
		fixture.refresh()

		#expect(fixture.model.favoriteRows.map(\.title) == ["#account"])
		#expect(fixture.model.selectableItems.contains { $0 === fixture.accountChannel })
	}

	@Test("What the bouncer says about a network shows under its name, and nothing while it is up")
	func statusRows() throws {
		let fixture = Fixture()
		func status(of session: ServerSession) throws -> BouncerNetworkStatus? {
			fixture.refresh()
			let account = try #require(fixture.model.rows.first)
			return try #require(account.networks.first { $0.id == session.uniqueIdentifier }).bouncerStatus
		}

		#expect(try status(of: fixture.libera) == nil)
		fixture.libera.bouncer.networkState = .connected
		#expect(try status(of: fixture.libera) == nil)
		fixture.libera.bouncer.networkState = .connecting
		#expect(try status(of: fixture.libera) == .connecting)
		fixture.libera.bouncer.networkState = .disconnected
		#expect(try status(of: fixture.libera) == .disconnected)
		fixture.libera.bouncer.networkError = "Connection refused"
		#expect(try status(of: fixture.libera) == .failed("Connection refused"))
		fixture.libera.config.bouncerNetwork?.isRemoved = true
		#expect(try status(of: fixture.libera) == .removed)
		#expect(fixture.model.rows.last?.bouncerStatus == nil)
		#expect(fixture.model.rows.first?.bouncerStatus == nil)
	}

	@Test("A filter that matches a channel of a network keeps the account and the network around it")
	func filterKeepsTheAncestors() throws {
		let fixture = Fixture()
		fixture.model.filterText = "kernel"

		let account = try #require(fixture.model.rows.first)
		#expect(fixture.model.rows.map(\.title) == ["Account"])
		#expect(account.networks.map(\.title) == ["OFTC"])
		#expect(account.conversations.isEmpty)
		#expect(account.networks.first?.conversations.map(\.title) == ["#kernel"])
		#expect(account.isExpanded)
	}

	@Test("The outline tree nests a network's node and its channels inside the account's node")
	func treeNestsNodes() throws {
		let fixture = Fixture()
		let tree = SidebarOutlineTree()

		tree.apply(SidebarOutlineSnapshot(model: fixture.model))

		let account = try #require(tree.nodes[.server(fixture.account.uniqueIdentifier)])
		#expect(account.children.map(\.identity) == [
			.conversation(fixture.accountChannel.uniqueIdentifier),
			.server(fixture.libera.uniqueIdentifier),
			.server(fixture.oftc.uniqueIdentifier),
		])
		let libera = try #require(tree.nodes[.server(fixture.libera.uniqueIdentifier)])
		#expect(libera.parentIdentifier == fixture.account.uniqueIdentifier)
		#expect(libera.children.map(\.identity) == [.conversation(fixture.liberaChannel.uniqueIdentifier)])
		#expect(tree.roots.map(\.identity) == [
			.server(fixture.account.uniqueIdentifier), .server(fixture.plain.uniqueIdentifier),
		])
	}

	@Test("A network promoted to the top level has no parent in the outline")
	func promotedNodeLosesItsParent() throws {
		let fixture = Fixture()
		let tree = SidebarOutlineTree()
		tree.apply(SidebarOutlineSnapshot(model: fixture.model))
		let libera = try #require(tree.nodes[.server(fixture.libera.uniqueIdentifier)])
		#expect(libera.parentIdentifier != nil)

		fixture.account.config.bouncerHidesParent = true
		fixture.refresh()
		tree.apply(SidebarOutlineSnapshot(model: fixture.model))

		#expect(tree.nodes[.server(fixture.libera.uniqueIdentifier)] === libera)
		#expect(libera.parentIdentifier == nil)
	}

	@Test("The accessibility description of a network includes what the bouncer says about it")
	func accessibilityIncludesStatus() throws {
		let fixture = Fixture()
		fixture.libera.bouncer.networkError = "Connection refused"
		fixture.refresh()
		let tree = SidebarOutlineTree()
		tree.apply(SidebarOutlineSnapshot(model: fixture.model))

		let node = try #require(tree.nodes[.server(fixture.libera.uniqueIdentifier)])

		#expect(node.accessibilityDescription.contains("Connection refused"))
	}
}

/// Reordering inside the native outline: a network moves among its account's
/// networks, never out of it or among its channels.
@MainActor
@Suite("Sidebar bouncer reordering", .serialized)
struct SidebarBouncerReorderingTests {
	private final class Fixture {
		let model = Sidebar()
		let chat = ChatSession()
		let account = TestServerSession()
		let libera = TestServerSession()
		let oftc = TestServerSession()
		let rizon = TestServerSession()
		let channel: Conversation
		let outline: SidebarOutlineView
		let window: NSWindow

		init() {
			account.config.connectionName = "Account"
			libera.config.connectionName = "Libera"
			oftc.config.connectionName = "OFTC"
			rizon.config.connectionName = "Rizon"
			for (session, network) in [(libera, "1"), (oftc, "2"), (rizon, "3")] {
				session.config.bouncerNetwork = BouncerNetworkBinding(
					parentIdentifier: account.uniqueIdentifier, networkIdentifier: network
				)
			}
			channel = Conversation(config: ConversationConfig(name: "#account"))
			channel.associatedSession = account
			account.conversationList = [channel]
			for session in [account, libera, oftc, rizon] {
				session.sidebarItemIsExpanded = true
			}
			chat.sessions = [account, libera, oftc, rizon]
			let chat = chat
			model.chatSessionSource = { chat }
			model.filterText = ""
			outline = SidebarOutlineView(model: model, redirectTyping: { _ in })
			let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 420))
			outline.frame = scroll.bounds
			scroll.documentView = outline
			window = NSWindow(contentRect: scroll.frame, styleMask: .borderless, backing: .buffered, defer: false)
			window.isReleasedWhenClosed = false
			window.contentView = scroll
			apply()
		}

		func apply() {
			outline.apply(SidebarOutlineSnapshot(model: model))
			window.contentView?.layoutSubtreeIfNeeded()
		}

		func close() {
			outline.stopUpdates()
			window.close()
		}

		var networkOrder: [String] {
			BouncerHierarchy(sessions: chat.sessions).children(of: account).map(\.label)
		}
	}

	@Test("Every node of a nested sidebar is a row, parents before the networks inside them")
	func nestedRowsAreDrawn() {
		let fixture = Fixture()
		defer { fixture.close() }

		let titles = (0 ..< fixture.outline.numberOfRows).compactMap { index -> String? in
			switch fixture.outline.node(at: index)?.content {
			case let .server(server): server.title
			case let .conversation(conversation): conversation.title
			case nil: nil
			}
		}
		#expect(titles == ["Account", "#account", "Libera", "OFTC", "Rizon"])
	}

	@Test("A network moves up and down among its account's networks")
	func networksReorderWithinTheirAccount() {
		let fixture = Fixture()
		defer { fixture.close() }
		let rizon = SidebarNodeID.server(fixture.rizon.uniqueIdentifier)

		#expect(fixture.outline.canMove(rizon, upward: true))
		#expect(fixture.outline.canMove(rizon, upward: false) == false)
		#expect(fixture.outline.move(rizon, upward: true))

		#expect(fixture.networkOrder == ["Libera", "Rizon", "OFTC"])
	}

	@Test("The first network cannot move up, and a network never moves out of its account")
	func movesStayInsideTheAccount() {
		let fixture = Fixture()
		defer { fixture.close() }
		let libera = SidebarNodeID.server(fixture.libera.uniqueIdentifier)

		#expect(fixture.outline.canMove(libera, upward: true) == false)
		#expect(fixture.outline.proposedMove(identity: libera, parent: nil, childIndex: 0) == nil)
	}

	@Test("A channel never moves among the networks, nor a network among the channels")
	func channelsAndNetworksStayApart() {
		let fixture = Fixture()
		defer { fixture.close() }
		let channel = SidebarNodeID.conversation(fixture.channel.uniqueIdentifier)
		let oftc = SidebarNodeID.server(fixture.oftc.uniqueIdentifier)
		let account = fixture.account.uniqueIdentifier

		#expect(fixture.outline.canMove(channel, upward: false) == false)
		#expect(fixture.outline.proposedMove(identity: channel, parent: account, childIndex: 2) == nil)
		#expect(fixture.outline.proposedMove(identity: oftc, parent: account, childIndex: -1) == nil)
	}

	@Test("A move among networks is placed relative to the networks alone")
	func moveIndexSkipsTheChannels() throws {
		let fixture = Fixture()
		defer { fixture.close() }
		let oftc = SidebarNodeID.server(fixture.oftc.uniqueIdentifier)

		// Positions among networks start at zero, though the account draws a channel first.
		let move = try #require(fixture.outline.proposedMove(identity: oftc, parent: fixture.account.uniqueIdentifier, childIndex: 0))

		#expect(move.before == fixture.libera.uniqueIdentifier)
		#expect(move.parent == fixture.account.uniqueIdentifier)
	}

	@Test("The saved order of a network moved before its siblings survives a rebuild")
	func orderSurvivesRebuild() {
		let fixture = Fixture()
		defer { fixture.close() }
		#expect(fixture.outline.move(.server(fixture.oftc.uniqueIdentifier), upward: true))

		fixture.model.filterText = ""
		fixture.apply()

		let titles = (0 ..< fixture.outline.numberOfRows).compactMap { index -> String? in
			if case let .server(server)? = fixture.outline.node(at: index)?.content {
				server.title
			} else {
				nil
			}
		}
		#expect(titles == ["Account", "OFTC", "Libera", "Rizon"])
	}
}
