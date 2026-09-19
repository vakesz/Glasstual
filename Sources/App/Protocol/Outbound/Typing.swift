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

/// The client-only tag a typing notification travels in.
private let typingTagName = "+typing"

enum OutboundTypingPolicy {
	static let activeInterval: TimeInterval = 3
	static let pausedDelay: TimeInterval = 5

	static func shouldFinish(text: String, notificationsEnabled: Bool) -> Bool {
		text.isEmpty || text.hasPrefix("/") || notificationsEnabled == false
	}

	static func shouldSendActive(previousState: TypingState?, lastSentAt: Date?, now: Date) -> Bool {
		guard previousState == .active, let lastSentAt else { return true }
		return now.timeIntervalSince(lastSentAt) >= activeInterval
	}
}

extension ServerSession {
	func typingNotificationsAvailable(for conversation: Conversation?) -> Bool {
		guard let conversation, conversation.isConsole == false else { return false }
		guard conversation.isChannel || conversation.isDirect else { return false }
		return isLoggedIn && isCapabilityEnabled(.messageTags) && isClientTagPermitted(typingTagName)
	}

	func noteLocalUserTyping(_ text: String, in conversation: Conversation?) {
		noteLocalUserTyping(text, in: conversation, at: Date())
	}

	func noteLocalUserTyping(_ text: String, in conversation: Conversation?, at date: Date) {
		guard typingNotificationsAvailable(for: conversation), let conversation else { return }

		if OutboundTypingPolicy.shouldFinish(
			text: text,
			notificationsEnabled: environment.settings.sendTypingNotifications
		) {
			sendTypingDone(in: conversation)
			return
		}

		let key = conversation.uniqueIdentifier

		if OutboundTypingPolicy.shouldSendActive(
			previousState: typingStateSent[key],
			lastSentAt: typingActiveSentAt[key],
			now: date
		), sendTagMessage([typingTagName: TypingState.active.rawValue], toTarget: conversation.name) {
			typingActiveSentAt[key] = date
			typingStateSent[key] = .active
		}

		scheduleTypingPause(for: conversation)
	}

	/// Replaces the pending "paused" notification for `conversation`.
	private func scheduleTypingPause(for conversation: Conversation) {
		let key = conversation.uniqueIdentifier
		cancelTypingPause(forKey: key)

		typingPauseTasks[key] = Task { [weak self] in
			try? await Task.sleep(for: .seconds(OutboundTypingPolicy.pausedDelay))

			guard Task.isCancelled == false, let self else { return }

			typingPauseTasks.removeValue(forKey: key)
			typingPauseTimerFired(conversation)
		}
	}

	private func cancelTypingPause(forKey key: String) {
		typingPauseTasks.removeValue(forKey: key)?.cancel()
	}

	func typingPauseTimerFired(_ conversation: Conversation) {
		let key = conversation.uniqueIdentifier
		guard typingStateSent[key] == .active else { return }

		guard typingNotificationsAvailable(for: conversation) else {
			typingStateSent.removeValue(forKey: key)
			return
		}

		if sendTagMessage([typingTagName: TypingState.paused.rawValue], toTarget: conversation.name) {
			typingStateSent[key] = .paused
		}
	}

	func sendTypingDone(in conversation: Conversation?) {
		guard let conversation else { return }
		let key = conversation.uniqueIdentifier

		cancelTypingPause(forKey: key)

		guard typingStateSent[key] != nil else { return }
		typingStateSent.removeValue(forKey: key)
		typingActiveSentAt.removeValue(forKey: key)

		if typingNotificationsAvailable(for: conversation) {
			_ = sendTagMessage([typingTagName: TypingState.done.rawValue], toTarget: conversation.name)
		}
	}

	func localUserSentMessage(in conversation: Conversation?) {
		sendTypingDone(in: conversation)
	}

	func localUserClearedText(in conversation: Conversation?) {
		sendTypingDone(in: conversation)
	}
}
