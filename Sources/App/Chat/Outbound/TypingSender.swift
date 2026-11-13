// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The `+typing` states the session tells the server about.
nonisolated enum TypingState: String, Sendable {
	case active
	case paused
	case done
}

/// Owns the notices and pause timers for one IRC connection. Each entry belongs
/// to the destination that received its active notice.
@MainActor
final class TypingSender {
	private struct Entry {
		let target: String
		var activity: TypingState
		var lastSentAt: Date
		let timer: SessionTimer
	}

	private static let tag = "+typing"
	private static let minimumInterval: TimeInterval = 3
	private static let pauseDelay: TimeInterval = 5
	private weak var session: ServerSession?
	private var entries: [String: Entry] = [:]

	init(session: ServerSession) {
		self.session = session
	}

	func isAvailable(in conversation: Conversation?) -> Bool {
		guard let session, let conversation,
		      session.isLoggedIn, !session.isTerminating, !session.isQuitting, !session.isDisconnecting,
		      session.environment.settings.sendTypingNotifications,
		      session.isCapabilityEnabled(.messageTags), session.isClientTagPermitted(Self.tag),
		      conversation.isActive, conversation.isChannel || conversation.isDirect,
		      conversation.associatedSession === session
		else { return false }
		return session.conversationList.contains { $0 === conversation }
	}

	func noteText(_ text: String, in conversation: Conversation?, at date: Date = Date()) {
		guard let conversation else { return }
		guard isAvailable(in: conversation) else {
			remove(in: conversation)
			return
		}
		guard !text.isEmpty, !text.hasPrefix("/") else {
			finish(in: conversation, at: date)
			return
		}

		let key = conversation.uniqueIdentifier
		if entries[key]?.target != conversation.name {
			remove(in: conversation)
		}
		if var entry = entries[key], date.timeIntervalSince(entry.lastSentAt) < Self.minimumInterval {
			entry.activity = .active
			entries[key] = entry
			entry.timer.start(Self.pauseDelay)
			return
		}
		guard send(.active, to: conversation.name) else {
			remove(in: conversation)
			return
		}
		let timer = entries[key]?.timer ?? SessionTimer { [weak self, weak conversation] _ in
			guard let conversation else { return }
			self?.timerFired(in: conversation)
		}
		entries[key] = Entry(target: conversation.name, activity: .active, lastSentAt: date, timer: timer)
		timer.start(Self.pauseDelay)
	}

	func pause(in conversation: Conversation, at date: Date = Date()) {
		let key = conversation.uniqueIdentifier
		guard let entry = entries[key] else { return }
		entry.timer.stop()
		guard isAvailable(in: conversation), entry.target == conversation.name else {
			remove(in: conversation)
			return
		}
		guard entry.activity == .active, date.timeIntervalSince(entry.lastSentAt) >= Self.minimumInterval else { return }
		if send(.paused, to: entry.target) {
			entries[key]?.activity = .paused
			entries[key]?.lastSentAt = date
		} else {
			remove(in: conversation)
		}
	}

	func finish(in conversation: Conversation?, at date: Date = Date()) {
		guard let conversation, var entry = entries[conversation.uniqueIdentifier] else { return }
		guard isAvailable(in: conversation), entry.target == conversation.name else {
			remove(in: conversation)
			return
		}
		guard entry.activity != .done else { return }
		if date.timeIntervalSince(entry.lastSentAt) >= Self.minimumInterval, send(.done, to: entry.target) {
			entry.lastSentAt = date
		}
		// Keep the cooldown when input is cleared and immediately starts again.
		// A done notice is optional; the peer also clears typing on a message or timeout.
		entry.activity = .done
		entries[conversation.uniqueIdentifier] = entry
		let remaining = Self.minimumInterval - date.timeIntervalSince(entry.lastSentAt)
		if remaining > 0 {
			entry.timer.start(remaining)
		} else {
			remove(in: conversation)
		}
	}

	private func timerFired(in conversation: Conversation) {
		if entries[conversation.uniqueIdentifier]?.activity == .done {
			remove(in: conversation)
		} else {
			pause(in: conversation)
		}
	}

	func remove(in conversation: Conversation) {
		entries.removeValue(forKey: conversation.uniqueIdentifier)?.timer.stop()
	}

	func removeAll() {
		for entry in entries.values {
			entry.timer.stop()
		}
		entries.removeAll()
	}

	private func send(_ state: TypingState, to target: String) -> Bool {
		session?.sendTagMessage([Self.tag: state.rawValue], toTarget: target) == true
	}
}
