// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension Notification.Name {
	static let typingTrackerDidChange = Self("Glasstual.typingTrackerDidChange")
}

nonisolated let typingTrackerConversationKey = "channel"

private struct TypingEntry {
	let nickname: String
	let sequence: UInt
	var state: TypingState
	var updatedAt: Date

	var expiresAt: Date {
		let timeout = state == .active ? 6.0 : 30.0

		return updatedAt.addingTimeInterval(timeout)
	}
}

private final class TypingBucket {
	weak var conversation: Conversation?
	var entries: [String: TypingEntry] = [:]

	init(conversation: Conversation) {
		self.conversation = conversation
	}
}

final class TypingTracker {
	private weak var session: ServerSession?

	private var buckets: [String: TypingBucket] = [:]
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
		let bucket = buckets[conversationKey] ?? TypingBucket(conversation: conversation)
		let existingEntry = bucket.entries[nicknameKey]
		var changed = false

		if state == .done {
			if existingEntry != nil {
				bucket.entries.removeValue(forKey: nicknameKey)
				changed = true
			}
		} else if var existingEntry {
			changed = existingEntry.state != state
			existingEntry.state = state
			existingEntry.updatedAt = date
			bucket.entries[nicknameKey] = existingEntry
		} else {
			sequence += 1
			bucket.entries[nicknameKey] = TypingEntry(
				nickname: nickname,
				sequence: sequence,
				state: state,
				updatedAt: date
			)
			bucket.conversation = conversation
			changed = true
		}

		if bucket.entries.isEmpty {
			buckets.removeValue(forKey: conversationKey)
		} else {
			buckets[conversationKey] = bucket
		}

		scheduleExpiry()

		if changed {
			postChange(for: conversation)
		}
	}

	func removeNickname(_ nickname: String) {
		let nicknameKey = casefolded(nickname)

		for conversationKey in Array(buckets.keys) {
			guard let bucket = buckets[conversationKey], bucket.entries.removeValue(forKey: nicknameKey) != nil
			else {
				continue
			}

			if bucket.entries.isEmpty {
				buckets.removeValue(forKey: conversationKey)
			}

			if let conversation = bucket.conversation {
				postChange(for: conversation)
			}
		}
		scheduleExpiry()
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

		guard buckets.removeValue(forKey: conversationKey) != nil else {
			return
		}

		scheduleExpiry()
		postChange(for: conversation)
	}

	func removeAll() {
		let conversations = buckets.values.compactMap(\.conversation)
		buckets.removeAll()
		for conversation in conversations {
			postChange(for: conversation)
		}
		expiryTimer.stop()
	}

	func typingNicknames(in conversation: Conversation) -> [String] {
		typingNicknames(in: conversation, at: Date())
	}

	func typingNicknames(in conversation: Conversation, at date: Date) -> [String] {
		guard let conversationEntries = buckets[conversation.uniqueIdentifier]?.entries else {
			return []
		}

		return conversationEntries.values
			.filter { $0.expiresAt >= date }
			.sorted { $0.sequence < $1.sequence }
			.map(\.nickname)
	}

	func expireEntries(at date: Date) {
		for conversationKey in Array(buckets.keys) {
			guard let bucket = buckets[conversationKey] else {
				continue
			}

			let oldCount = bucket.entries.count
			bucket.entries = bucket.entries.filter { $0.value.expiresAt >= date }
			let changed = bucket.entries.count != oldCount

			if bucket.entries.isEmpty {
				buckets.removeValue(forKey: conversationKey)
			}

			if changed, let conversation = bucket.conversation {
				postChange(for: conversation)
			}
		}

		scheduleExpiry()
	}

	private func scheduleExpiry() {
		guard buckets.isEmpty == false else {
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
