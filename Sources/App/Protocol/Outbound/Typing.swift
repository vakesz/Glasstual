// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The `+typing` states the client tells the server about.
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

extension Client {
	func typingNotificationsAvailable(for channel: Channel?) -> Bool {
		guard let channel, channel.isUtility == false else { return false }
		guard channel.isChannel || channel.isPrivateMessage else { return false }
		return isLoggedIn && isCapabilityEnabled(.messageTags) && isClientTagPermitted(typingTagName)
	}

	func noteLocalUserTyping(_ text: String, in channel: Channel?) {
		noteLocalUserTyping(text, in: channel, at: Date())
	}

	func noteLocalUserTyping(_ text: String, in channel: Channel?, at date: Date) {
		guard typingNotificationsAvailable(for: channel), let channel else { return }

		if OutboundTypingPolicy.shouldFinish(
			text: text,
			notificationsEnabled: environment.preferences.sendTypingNotifications
		) {
			sendTypingDone(in: channel)
			return
		}

		let key = channel.uniqueIdentifier

		if OutboundTypingPolicy.shouldSendActive(
			previousState: typingStateSent[key],
			lastSentAt: typingActiveSentAt[key],
			now: date
		), sendTagMessage([typingTagName: TypingState.active.rawValue], toTarget: channel.name) {
			typingActiveSentAt[key] = date
			typingStateSent[key] = .active
		}

		scheduleTypingPause(for: channel)
	}

	/// Replaces the pending "paused" notification for `channel`.
	private func scheduleTypingPause(for channel: Channel) {
		let key = channel.uniqueIdentifier
		cancelTypingPause(forKey: key)

		typingPauseTasks[key] = Task { [weak self] in
			try? await Task.sleep(for: .seconds(OutboundTypingPolicy.pausedDelay))

			guard Task.isCancelled == false, let self else { return }

			typingPauseTasks.removeValue(forKey: key)
			typingPauseTimerFired(channel)
		}
	}

	private func cancelTypingPause(forKey key: String) {
		typingPauseTasks.removeValue(forKey: key)?.cancel()
	}

	func typingPauseTimerFired(_ channel: Channel) {
		let key = channel.uniqueIdentifier
		guard typingStateSent[key] == .active else { return }

		guard typingNotificationsAvailable(for: channel) else {
			typingStateSent.removeValue(forKey: key)
			return
		}

		if sendTagMessage([typingTagName: TypingState.paused.rawValue], toTarget: channel.name) {
			typingStateSent[key] = .paused
		}
	}

	func sendTypingDone(in channel: Channel?) {
		guard let channel else { return }
		let key = channel.uniqueIdentifier

		cancelTypingPause(forKey: key)

		guard typingStateSent[key] != nil else { return }
		typingStateSent.removeValue(forKey: key)
		typingActiveSentAt.removeValue(forKey: key)

		if typingNotificationsAvailable(for: channel) {
			_ = sendTagMessage([typingTagName: TypingState.done.rawValue], toTarget: channel.name)
		}
	}

	func localUserSentMessage(in channel: Channel?) {
		sendTypingDone(in: channel)
	}

	func localUserClearedText(in channel: Channel?) {
		sendTypingDone(in: channel)
	}
}
