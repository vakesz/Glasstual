// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Server session shell policies")
struct ServerSessionShellPolicyTests {
	@Test("Channels are stored ahead of queries")
	func channelStoragePlacesChannelsBeforeQueries() {
		let session = TestServerSession()

		session.add(Conversation(config: ConversationConfig(name: "#first")))
		session.add(Conversation(config: ConversationConfig(name: "someone", type: .direct)))
		session.add(Conversation(config: ConversationConfig(name: "#second")))
		session.add(Conversation(config: ConversationConfig(name: "other", type: .direct)))

		#expect(session.conversationList.map(\.name) == ["#first", "#second", "someone", "other"])
	}

	@Test("A console window or a direct chat is never written to the stored configuration")
	func storedConfigurationExcludesTransientChannels() {
		#expect(
			ServerConfigPolicy.shouldStoreConversation(
				isConsole: true,
				isDirectChat: false,
				isChannel: true,
				rememberDirectConversations: true
			) == false
		)
		#expect(
			ServerConfigPolicy.shouldStoreConversation(
				isConsole: false,
				isDirectChat: true,
				isChannel: false,
				rememberDirectConversations: true
			) == false
		)
	}

	@Test("A query is stored only while the remember-queries preference is on")
	func storedConfigurationHonorsQueryPreference() {
		#expect(
			ServerConfigPolicy.shouldStoreConversation(
				isConsole: false,
				isDirectChat: false,
				isChannel: false,
				rememberDirectConversations: false
			) == false
		)
		#expect(
			ServerConfigPolicy.shouldStoreConversation(
				isConsole: false,
				isDirectChat: false,
				isChannel: false,
				rememberDirectConversations: true
			)
		)
	}
}
