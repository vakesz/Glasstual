/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

enum OutboundTypingPolicy {
	static let activeInterval: TimeInterval = 3
	static let pausedDelay: TimeInterval = 5

	static func shouldFinish(text: String, notificationsEnabled: Bool) -> Bool {
		text.isEmpty || text.hasPrefix("/") || notificationsEnabled == false
	}

	static func shouldSendActive(previousState: String?, lastSentAt: Date?, now: Date) -> Bool {
		guard previousState == "active", let lastSentAt else { return true }
		return now.timeIntervalSince(lastSentAt) >= activeInterval
	}
}

public extension IRCClient {
	@objc(typingNotificationsAvailableForChannel:)
	func typingNotificationsAvailable(for channel: IRCChannel?) -> Bool {
		guard let channel, channel.isUtility == false else { return false }
		guard channel.isChannel || channel.isPrivateMessage else { return false }
		return isLoggedIn && isCapabilityEnabled(.messageTags)
	}

	@objc(noteLocalUserTyping:inChannel:)
	func noteLocalUserTyping(_ text: String, in channel: IRCChannel?) {
		noteLocalUserTyping(text, in: channel, at: Date())
	}

	@objc(noteLocalUserTyping:inChannel:atDate:)
	func noteLocalUserTyping(_ text: String, in channel: IRCChannel?, at date: Date) {
		guard typingNotificationsAvailable(for: channel), let channel else { return }

		if OutboundTypingPolicy.shouldFinish(
			text: text,
			notificationsEnabled: TextualPreferences.sendTypingNotifications()
		) {
			sendTypingDone(in: channel)
			return
		}

		let key = channel.uniqueIdentifier
		let previousState = typingStateSent[key] as? String
		let lastSentAt = typingActiveSentAt[key] as? Date

		if OutboundTypingPolicy.shouldSendActive(previousState: previousState, lastSentAt: lastSentAt, now: date),
		   sendTagMessage(["+typing": "active"], toTarget: channel.name)
		{
			typingActiveSentAt[key] = date
			typingStateSent[key] = "active"
		}

		NSObject.cancelPreviousPerformRequests(
			withTarget: self,
			selector: #selector(typingPauseTimerFired(_:)),
			object: channel
		)
		perform(#selector(typingPauseTimerFired(_:)), with: channel, afterDelay: OutboundTypingPolicy.pausedDelay)
	}

	@objc(typingPauseTimerFired:)
	func typingPauseTimerFired(_ channel: IRCChannel) {
		let key = channel.uniqueIdentifier
		guard typingStateSent[key] as? String == "active" else { return }

		guard typingNotificationsAvailable(for: channel) else {
			typingStateSent.removeObject(forKey: key)
			return
		}

		if sendTagMessage(["+typing": "paused"], toTarget: channel.name) {
			typingStateSent[key] = "paused"
		}
	}

	@objc(sendTypingDoneInChannel:)
	func sendTypingDone(in channel: IRCChannel?) {
		guard let channel else { return }
		let key = channel.uniqueIdentifier

		NSObject.cancelPreviousPerformRequests(
			withTarget: self,
			selector: #selector(typingPauseTimerFired(_:)),
			object: channel
		)

		guard typingStateSent[key] != nil else { return }
		typingStateSent.removeObject(forKey: key)
		typingActiveSentAt.removeObject(forKey: key)

		if typingNotificationsAvailable(for: channel) {
			_ = sendTagMessage(["+typing": "done"], toTarget: channel.name)
		}
	}

	@objc(localUserSentMessageInChannel:)
	func localUserSentMessage(in channel: IRCChannel?) {
		sendTypingDone(in: channel)
	}

	@objc(localUserClearedTextInChannel:)
	func localUserClearedText(in channel: IRCChannel?) {
		sendTypingDone(in: channel)
	}
}
