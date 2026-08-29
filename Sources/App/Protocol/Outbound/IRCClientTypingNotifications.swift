/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/// The `+typing` states the client tells the server about.
nonisolated enum TypingState: String, Sendable { // nonisolated: value
	case active
	case paused
	case done
}

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

public extension IRCClient {
	func typingNotificationsAvailable(for channel: IRCChannel?) -> Bool {
		guard let channel, channel.isUtility == false else { return false }
		guard channel.isChannel || channel.isPrivateMessage else { return false }
		return isLoggedIn && isCapabilityEnabled(.messageTags)
	}

	func noteLocalUserTyping(_ text: String, in channel: IRCChannel?) {
		noteLocalUserTyping(text, in: channel, at: Date())
	}

	func noteLocalUserTyping(_ text: String, in channel: IRCChannel?, at date: Date) {
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
		), sendTagMessage(["+typing": TypingState.active.rawValue], toTarget: channel.name) {
			typingActiveSentAt[key] = date
			typingStateSent[key] = .active
		}

		scheduleTypingPause(for: channel)
	}

	/// Replaces the pending "paused" notification for `channel`.
	private func scheduleTypingPause(for channel: IRCChannel) {
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

	func typingPauseTimerFired(_ channel: IRCChannel) {
		let key = channel.uniqueIdentifier
		guard typingStateSent[key] == .active else { return }

		guard typingNotificationsAvailable(for: channel) else {
			typingStateSent.removeValue(forKey: key)
			return
		}

		if sendTagMessage(["+typing": TypingState.paused.rawValue], toTarget: channel.name) {
			typingStateSent[key] = .paused
		}
	}

	func sendTypingDone(in channel: IRCChannel?) {
		guard let channel else { return }
		let key = channel.uniqueIdentifier

		cancelTypingPause(forKey: key)

		guard typingStateSent[key] != nil else { return }
		typingStateSent.removeValue(forKey: key)
		typingActiveSentAt.removeValue(forKey: key)

		if typingNotificationsAvailable(for: channel) {
			_ = sendTagMessage(["+typing": TypingState.done.rawValue], toTarget: channel.name)
		}
	}

	func localUserSentMessage(in channel: IRCChannel?) {
		sendTypingDone(in: channel)
	}

	func localUserClearedText(in channel: IRCChannel?) {
		sendTypingDone(in: channel)
	}
}
