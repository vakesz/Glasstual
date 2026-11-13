// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

@MainActor
@Suite("Sidebar favorites and attention filters")
struct SidebarFavoritesTests {
	private let model = Sidebar()
	private let first = TestServerSession()
	private let second = TestServerSession()
	private let chat = ChatSession()
	private let channel = Conversation(config: ConversationConfig(name: "#swift"))
	private let otherChannel = Conversation(config: ConversationConfig(name: "#swift"))
	private let direct = Conversation(config: ConversationConfig(name: "alice", type: .direct))

	init() {
		first.config.connectionName = "Alpha"
		second.config.connectionName = "Beta"
		first.sidebarItemIsExpanded = true
		second.sidebarItemIsExpanded = false
		channel.associatedSession = first
		direct.associatedSession = first
		otherChannel.associatedSession = second
		first.conversationList = [channel, direct]
		second.conversationList = [otherChannel]
		chat.sessions = [first, second]
		let chat = chat
		model.chatSessionSource = { chat }
		model.filterText = ""
	}

	@Test("Favorites combine channels and private conversations without changing network order")
	func favoritesAcrossNetworks() {
		model.toggleFavorite(otherChannel)
		model.toggleFavorite(direct)
		model.toggleFavorite(channel)

		#expect(model.favoriteRows.map(\.id) == [channel, direct, otherChannel].map(\.uniqueIdentifier))
		#expect(model.favoriteRows.map(\.networkTitle) == ["Alpha", "Alpha", "Beta"])
		#expect(first.conversationList == [channel, direct])
		#expect(second.conversationList == [otherChannel])
		#expect(model.rows.map(\.id) == [first, second].map(\.uniqueIdentifier))
		#expect(first.config.conversationList.allSatisfy { conversation in conversation.isFavorite })
		#expect(model.row(forItem: otherChannel) >= 0)

		model.select(otherChannel)
		model.toggleFavorite(otherChannel)
		#expect(model.selectedItem === otherChannel)
		#expect(model.row(forItem: otherChannel) >= 0)
		#expect(model.favoriteRows.map(\.id) == [channel, direct].map(\.uniqueIdentifier))
	}

	@Test("Unread and mention filters compose with search and keep favorites in sync")
	func attentionFiltersComposeWithSearch() {
		channel.unreadCount = 3
		direct.unreadCount = 1
		otherChannel.nicknameHighlightCount = 1
		otherChannel.unreadCount = 2
		model.toggleFavorite(channel)
		model.toggleFavorite(otherChannel)

		model.filter = .unread
		#expect(model.rows.flatMap(\.conversations).count == 3)
		#expect(model.favoriteRows.count == 2)
		#expect(model.rows.allSatisfy { row in row.isExpanded })

		model.filter = .mentions
		#expect(model.rows.flatMap(\.conversations).map(\.id) == [otherChannel.uniqueIdentifier])
		#expect(model.favoriteRows.map(\.networkTitle) == ["Beta"])
		model.filterText = "alice"
		#expect(model.hasNoFilterMatches)
		#expect(model.favoriteRows.isEmpty)
		model.filter = .unread
		#expect(model.rows.flatMap(\.conversations).map(\.id) == [direct.uniqueIdentifier])
	}

	@Test("Reading a filtered conversation preserves selection when its row disappears")
	func readConversationRemainsSelected() {
		otherChannel.unreadCount = 1
		model.filter = .unread
		model.select(otherChannel)
		#expect(model.selectedItem === otherChannel)
		otherChannel.unreadCount = 0
		model.beginUpdates()
		model.setNeedsRefresh()
		model.endUpdates()

		#expect(model.hasNoFilterMatches)
		#expect(model.selectedItem === otherChannel)
		#expect(model.row(forItem: otherChannel) >= 0)
		#expect(second.sidebarItemIsExpanded == false)
		model.filter = .all
		#expect(model.selectedItem === otherChannel)
	}

	@Test("Muted highlights do not appear in Mentions but unread messages remain discoverable")
	func ignoredHighlightsAreExcluded() {
		var config = channel.config
		config.ignoreHighlights = true
		channel.updateConfig(config)
		channel.nicknameHighlightCount = 2
		channel.unreadCount = 2
		model.filter = .mentions
		#expect(model.hasNoFilterMatches)
		model.filter = .unread
		#expect(model.rows.flatMap(\.conversations).map(\.id) == [channel.uniqueIdentifier])
	}

	@Test("Favorites survive a server configuration round trip even when ordinary queries are forgotten")
	func favoritesPersistAcrossLaunches() throws {
		model.toggleFavorite(channel)
		model.toggleFavorite(direct)
		let ordinary = Conversation(config: ConversationConfig(name: "bob", type: .direct))
		var config = first.config
		config.conversationList = ServerConfigPolicy.storedConversationConfigurations(
			from: [channel, direct, ordinary], rememberDirectConversations: false
		)
		let restored = try #require(PropertyListModel.decode(ServerConfig.self, from: config.dictionaryValue))

		#expect(restored.conversationList.map(\.name) == ["#swift", "alice"])
		#expect(restored.conversationList.allSatisfy { conversation in conversation.isFavorite })
		#expect(restored.conversationList.map(\.uniqueIdentifier) == [channel, direct].map(\.uniqueIdentifier))
		model.toggleFavorite(direct)
		let afterUnpinning = ServerConfigPolicy.storedConversationConfigurations(
			from: [channel, direct], rememberDirectConversations: false
		)
		#expect(afterUnpinning.map(\.name) == ["#swift"])
	}

	@Test("Favorites are accepted by settings export and import validation")
	func favoritesTransfer() throws {
		model.toggleFavorite(direct)
		var config = first.config
		config.conversationList = [direct.config]
		let restored = try SettingsSessionArchive.decode(.array([.dictionary(SettingsSessionArchive.portableDictionary(config))]))
		#expect(restored.first?.conversationList.first?.isFavorite == true)
	}

	@Test("Transient consoles and DCC chats cannot be pinned", arguments: [ConversationKind.console, .directChat])
	func transientConversationsCannotBePinned(_ kind: ConversationKind) {
		let transient = Conversation(config: ConversationConfig(name: "transient", type: kind))
		transient.associatedSession = first
		first.conversationList.append(transient)
		model.toggleFavorite(transient)
		#expect(transient.config.isFavorite == false)
	}
}
