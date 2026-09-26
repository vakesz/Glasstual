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
	func resolveSecretKey(for conversation: Conversation) {
		let config = conversation.config
		let item = config.keychainItem
		guard !isTerminating, !isQuitting, !isDisconnecting,
		      isConnecting || isConnected,
		      conversation.associatedSession === self,
		      conversationList.contains(where: { $0 === conversation }),
		      config.pendingSecretKey == .unchanged,
		      sessionCredentials.hasResolved(item) == false,
		      startup.channelCredentialTasks[item] == nil
		else { return }

		let loadCredentials = credentialLoader
		let attempt = startup
		attempt.channelCredentialTasks[item] = Task { [weak self, weak conversation, weak attempt] in
			guard !Task.isCancelled else { return }
			let stored = await loadCredentials([item])
			guard !Task.isCancelled, let self, let attempt, startup === attempt else { return }
			defer { attempt.channelCredentialTasks[item] = nil }
			guard !isTerminating, !isQuitting, !isDisconnecting, isConnecting || isConnected,
			      let conversation, conversation.associatedSession === self,
			      conversationList.contains(where: { $0 === conversation }),
			      conversation.config.pendingSecretKey == .unchanged,
			      sessionCredentials.hasResolved(item) == false
			else { return }

			sessionCredentials.apply([item: stored[item].map { .set($0) } ?? .cleared])
		}
	}

	func remove(_ conversation: Conversation) {
		guard conversationListPrivate.contains(where: { $0 === conversation }) else { return }
		startup.channelCredentialTasks.removeValue(forKey: conversation.config.keychainItem)?.cancel()
		typingSender.remove(in: conversation)
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
