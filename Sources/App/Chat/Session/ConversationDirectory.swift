// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerSession {
	@MainActor
	func selectFirstConversation() {
		guard let first = conversationList.first else { return }

		output?.select(first)
	}

	/// Channels are kept ahead of the direct conversations, so a channel goes in
	/// front of the first non-channel and everything else goes on the end.
	func add(_ conversation: Conversation) {
		guard conversationListPrivate.contains(conversation) == false else { return }

		let index = conversation.isChannel
			? conversationListPrivate.firstIndex { $0.isChannel == false } ?? conversationListPrivate.endIndex
			: conversationListPrivate.endIndex

		conversationListPrivate.insert(conversation, at: index)
		updateStoredConversationList()
	}

	/** Reads a channel's stored JOIN key into the session's credentials.

	 Opening a connection resolves every channel's key in one batch, and nothing
	 reads a key before there is a connection to JOIN on, so the only channel
	 needing one of its own is one that arrived after that. */
	func resolveSecretKey(for config: ConversationConfig) {
		let item = config.keychainItem
		guard isConnecting || isConnected,
		      config.pendingSecretKey == .unchanged,
		      sessionCredentials.hasResolved(item) == false
		else { return }

		Task { [weak self] in
			let stored = await KeychainSecretLoader.passwords(for: [item])
			// An edit that landed while the read was in flight resolved the item
			// already, and it is the newer answer.
			guard let self, sessionCredentials.hasResolved(item) == false else { return }

			sessionCredentials.apply([item: stored[item].map { .set($0) } ?? .cleared])
		}
	}

	func remove(_ conversation: Conversation) {
		conversationListPrivate.removeAll { $0 === conversation }
		updateStoredConversationList()
	}

	var conversationCount: UInt {
		UInt(conversationListPrivate.count)
	}

	var conversationList: [Conversation] {
		get { conversationListPrivate }
		set {
			conversationListPrivate = newValue
			updateStoredConversationList()
		}
	}

	func conversation(at index: UInt) -> Conversation? {
		guard index < conversationListPrivate.count else { return nil }
		return conversationListPrivate[Int(index)]
	}
}

extension ServerSession {
	func findConversation(_ name: String, in conversationList: [Conversation]) -> Conversation? {
		let foldedName = casefoldNickname(name)
		return conversationList.first { casefoldNickname($0.name) == foldedName }
	}

	func findConversation(_ name: String) -> Conversation? {
		let foldedName = casefoldNickname(name)

		// A hit is only trusted while it still folds to the name asked for: a
		// rename or a new CASEMAPPING can invalidate the mirror between builds.
		if let hit = conversationIndex[foldedName: foldedName], casefoldNickname(hit.name) == foldedName {
			return hit
		}

		return conversationList.first { casefoldNickname($0.name) == foldedName }
	}

	/// Rebuilds the casefolded mirror of the conversation list.
	func rebuildConversationIndex() {
		conversationIndex.rebuild(from: conversationList, by: casefoldNickname, naming: \.name)
	}

	func findConversationOrCreate(_ name: String, isDirect: Bool = false) -> Conversation? {
		findConversationOrCreate(name, as: isDirect ? .direct : .channel)
	}

	func findConversationOrCreate(_ name: String, isConsole: Bool) -> Conversation? {
		findConversationOrCreate(name, as: isConsole ? .console : .channel)
	}

	func findConversationOrCreate(_ name: String, as type: ConversationKind) -> Conversation? {
		if let existing = findConversation(name) {
			return existing
		}

		guard let chatSession else { return nil }

		if type == .channel {
			let conversation = chatSession.createConversation(
				with: ConversationConfig.seed(withName: name),
				on: self,
				add: true,
				adjust: true,
				reload: true
			)
			chatSession.savePeriodically()
			return conversation
		}

		return chatSession.createDirectConversation(name, on: self, as: type)
	}
}
