// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Spotlight index plan")
struct ConversationIndexPlanTests {
	private let servers = [
		IntentServerSnapshot(id: "s1", name: "Libera", isConnected: true),
		IntentServerSnapshot(id: "s2", name: "OFTC", isConnected: false),
	]
	private let conversations = [
		IntentConversationSnapshot(id: "c1", serverID: "s1", serverName: "Libera", name: "#swift", kind: .channel),
		IntentConversationSnapshot(id: "c2", serverID: "s1", serverName: "Libera", name: "alice", kind: .directMessage),
	]

	private func entries(_ options: ConversationIndexOptions) -> [ConversationIndexEntry] {
		ConversationIndexPlan.entries(servers: servers, conversations: conversations, options: options)
	}

	@Test("Servers and channels are indexed by default and direct conversations are not")
	func defaultsKeepPeopleOut() {
		let result = entries(ConversationIndexOptions(indexesConversations: true, indexesDirectMessages: false))
		#expect(result.map(\.id) == ["s1", "s2", "c1"])
		#expect(result.map(\.kind) == [.server, .server, .channel])
	}

	@Test("Direct conversations join only when asked for")
	func directConversationsOptIn() {
		let result = entries(ConversationIndexOptions(indexesConversations: true, indexesDirectMessages: true))
		#expect(result.map(\.id) == ["s1", "s2", "c1", "c2"])
		#expect(result.last?.kind == .directMessage)
	}

	@Test("Nothing is indexed with the setting off, whatever the direct-message setting says")
	func offIndexesNothing() {
		#expect(entries(ConversationIndexOptions(indexesConversations: false, indexesDirectMessages: true)).isEmpty)
		#expect(entries(ConversationIndexOptions(indexesConversations: false, indexesDirectMessages: false)).isEmpty)
	}

	@Test("Empty titles and repeated identifiers are dropped")
	func cleansEntries() {
		let result = ConversationIndexPlan.entries(
			servers: [IntentServerSnapshot(id: "s1", name: "", isConnected: false)],
			conversations: [
				IntentConversationSnapshot(id: "c1", serverID: "s1", serverName: "", name: "#a", kind: .channel),
				IntentConversationSnapshot(id: "c1", serverID: "s1", serverName: "", name: "#b", kind: .channel),
			],
			options: ConversationIndexOptions(indexesConversations: true, indexesDirectMessages: false)
		)
		#expect(result.map(\.title) == ["#a"])
	}

	@Test("Only what changed is written, and what disappeared is deleted")
	func changes() {
		let options = ConversationIndexOptions(indexesConversations: true, indexesDirectMessages: true)
		let first = entries(options)
		let previous = Dictionary(uniqueKeysWithValues: first.map { ($0.id, $0) })

		#expect(ConversationIndexPlan.changes(from: previous, to: first).isEmpty)

		var renamed = first
		renamed[2] = ConversationIndexEntry(id: "c1", kind: .channel, title: "#swift-dev", serverID: "s1", serverName: "Libera")
		let rename = ConversationIndexPlan.changes(from: previous, to: renamed)
		#expect(rename.upserts.map(\.id) == ["c1"])
		#expect(rename.deletions.isEmpty)

		let removal = ConversationIndexPlan.changes(from: previous, to: first.filter { $0.id != "c2" && $0.id != "s2" })
		#expect(removal.upserts.isEmpty)
		#expect(removal.deletions == ["c2", "s2"])

		let cleared = ConversationIndexPlan.changes(from: previous, to: [])
		#expect(cleared.deletions == ["c1", "c2", "s1", "s2"])
	}

	@Test("Suggested conversations are none with indexing off")
	func suggestionsOffSuggestNothing() {
		let options = ConversationIndexOptions(indexesConversations: false, indexesDirectMessages: true)
		#expect(ConversationIndexPlan.suggestedConversations(conversations, options: options).isEmpty)
	}

	@Test("Suggested conversations leave out direct conversations by default")
	func suggestionsKeepPeopleOut() {
		let options = ConversationIndexOptions(indexesConversations: true, indexesDirectMessages: false)
		#expect(ConversationIndexPlan.suggestedConversations(conversations, options: options).map(\.id) == ["c1"])
	}

	@Test("Suggested conversations include direct conversations when opted in")
	func suggestionsIncludePeopleWhenAsked() {
		let options = ConversationIndexOptions(indexesConversations: true, indexesDirectMessages: true)
		#expect(ConversationIndexPlan.suggestedConversations(conversations, options: options).map(\.id) == ["c1", "c2"])
	}
}
