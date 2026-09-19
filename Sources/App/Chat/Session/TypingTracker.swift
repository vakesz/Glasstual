// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension Notification.Name {
	static let typingTrackerDidChange = Self("Glasstual.typingTrackerDidChange")
}

nonisolated let typingTrackerConversationKey = "channel"

private final class TypingEntry {
	let nickname: String
	let sequence: UInt
	var state: TypingState
	var updatedAt: Date

	init(nickname: String, sequence: UInt, state: TypingState, updatedAt: Date) {
		self.nickname = nickname
		self.sequence = sequence
		self.state = state
		self.updatedAt = updatedAt
	}

	var expiresAt: Date {
		let timeout = state == .active ? 6.0 : 30.0

		return updatedAt.addingTimeInterval(timeout)
	}
}

final class TypingTracker {
	private weak var session: ServerSession?

	private var entries: [String: [String: TypingEntry]] = [:]
	private let conversations = NSMapTable<NSString, Conversation>.strongToWeakObjects()
	/// Drops the indicators whose timeout has passed, for as long as there is
	/// one to drop.
	private lazy var expiryTimer = SessionTimer { [weak self] _ in
		self?.expireEntries(at: Date())
	}

	private var sequence: UInt = 0

	init(session: ServerSession) {
		self.session = session
	}

	/// The state a `+typing` tag stands for. An unknown value is read as
	/// `done`, which is what clears the indicator rather than leaving it up.
	static func state(forTagValue value: String?) -> TypingState {
		value.flatMap(TypingState.init(rawValue:)) ?? .done
	}

	func noteTypingState(
		_ state: TypingState,
		fromNickname nickname: String,
		in conversation: Conversation,
		at date: Date = Date()
	) {
		guard nickname.isEmpty == false else {
			return
		}

		let conversationKey = conversation.uniqueIdentifier
		let nicknameKey = casefolded(nickname)
		var conversationEntries = entries[conversationKey] ?? [:]
		let existingEntry = conversationEntries[nicknameKey]
		var changed = false

		if state == .done {
			if existingEntry != nil {
				conversationEntries.removeValue(forKey: nicknameKey)
				changed = true
			}
		} else if let existingEntry {
			changed = existingEntry.state != state
			existingEntry.state = state
			existingEntry.updatedAt = date
		} else {
			sequence += 1
			conversationEntries[nicknameKey] = TypingEntry(
				nickname: nickname,
				sequence: sequence,
				state: state,
				updatedAt: date
			)
			conversations.setObject(conversation, forKey: conversationKey as NSString)
			changed = true
		}

		if conversationEntries.isEmpty {
			entries.removeValue(forKey: conversationKey)
			conversations.removeObject(forKey: conversationKey as NSString)
		} else {
			entries[conversationKey] = conversationEntries
		}

		scheduleExpiry()

		if changed {
			postChange(for: conversation)
		}
	}

	func removeNickname(_ nickname: String) {
		let nicknameKey = casefolded(nickname)

		for conversationKey in Array(entries.keys) {
			guard var conversationEntries = entries[conversationKey], conversationEntries.removeValue(forKey: nicknameKey) != nil
			else {
				continue
			}

			let conversation = conversations.object(forKey: conversationKey as NSString)

			if conversationEntries.isEmpty {
				entries.removeValue(forKey: conversationKey)
				conversations.removeObject(forKey: conversationKey as NSString)
			} else {
				entries[conversationKey] = conversationEntries
			}

			if let conversation {
				postChange(for: conversation)
			}
		}
	}

	/** The key a nickname is filed under.

	 The server decides what two spellings of a nickname are the same one:
	 under RFC 1459 `nick[home]` and `nick{home}` are, and `lowercased()` says
	 they are not while also folding non-ASCII letters no server folds. A
	 typing indicator filed under one spelling then never cleared when the
	 `done` tag arrived spelled the other way. */
	private func casefolded(_ nickname: String) -> String {
		session?.casefoldNickname(nickname) ?? nickname.lowercased()
	}

	func removeAll(in conversation: Conversation) {
		let conversationKey = conversation.uniqueIdentifier

		guard entries.removeValue(forKey: conversationKey) != nil else {
			return
		}

		conversations.removeObject(forKey: conversationKey as NSString)
		postChange(for: conversation)
	}

	func removeAll() {
		let conversationKeys = Array(entries.keys)

		entries.removeAll()

		for conversationKey in conversationKeys {
			if let conversation = conversations.object(forKey: conversationKey as NSString) {
				postChange(for: conversation)
			}
		}

		conversations.removeAllObjects()
		expiryTimer.stop()
	}

	func typingNicknames(in conversation: Conversation) -> [String] {
		typingNicknames(in: conversation, at: Date())
	}

	func typingNicknames(in conversation: Conversation, at date: Date) -> [String] {
		guard let conversationEntries = entries[conversation.uniqueIdentifier] else {
			return []
		}

		return conversationEntries.values
			.filter { $0.expiresAt >= date }
			.sorted { $0.sequence < $1.sequence }
			.map(\.nickname)
	}

	func expireEntries(at date: Date) {
		for conversationKey in Array(entries.keys) {
			guard var conversationEntries = entries[conversationKey] else {
				continue
			}

			let oldCount = conversationEntries.count
			conversationEntries = conversationEntries.filter { $0.value.expiresAt >= date }
			let changed = conversationEntries.count != oldCount
			let conversation = conversations.object(forKey: conversationKey as NSString)

			if conversationEntries.isEmpty {
				entries.removeValue(forKey: conversationKey)
				conversations.removeObject(forKey: conversationKey as NSString)
			} else {
				entries[conversationKey] = conversationEntries
			}

			if changed, let conversation {
				postChange(for: conversation)
			}
		}

		scheduleExpiry()
	}

	private func scheduleExpiry() {
		guard entries.isEmpty == false else {
			expiryTimer.stop()
			return
		}

		expiryTimer.startIfIdle(1.0, repeats: true)
	}

	private func postChange(for conversation: Conversation) {
		guard let session else {
			return
		}

		NotificationCenter.default.post(
			name: .typingTrackerDidChange,
			object: session,
			userInfo: [typingTrackerConversationKey: conversation]
		)
	}
}
