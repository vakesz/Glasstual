/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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

private final class TypingEntry {
	let nickname: String
	let sequence: UInt
	var state: IRCTypingState
	var updatedAt: Date

	init(nickname: String, sequence: UInt, state: IRCTypingState, updatedAt: Date) {
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

private final class TypingTimerTarget: NSObject {
	weak var tracker: TypingTracker?

	init(tracker: TypingTracker) {
		self.tracker = tracker
	}

	@objc func timerFired(_: Timer) {
		tracker?.expireEntries(at: Date())
	}
}

@objc(IRCTypingTracker)
public final class TypingTracker: NSObject {
	private weak var client: IRCClient?

	private var entries: [String: [String: TypingEntry]] = [:]
	private let channels = NSMapTable<NSString, IRCChannel>.strongToWeakObjects()
	private var expiryTimer: Timer?
	private var sequence: UInt = 0
	private lazy var timerTarget = TypingTimerTarget(tracker: self)

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(client:)")
	}

	@objc(initWithClient:)
	public init(client: IRCClient) {
		self.client = client

		super.init()
	}

	deinit {
		expiryTimer?.invalidate()
	}

	@objc(stateForTagValue:)
	public static func state(forTagValue value: String?) -> IRCTypingState {
		switch value {
		case "active":
			.active
		case "paused":
			.paused
		default:
			.done
		}
	}

	@objc(noteTypingState:fromNickname:inChannel:)
	public func noteTypingState(
		_ state: IRCTypingState,
		fromNickname nickname: String,
		in channel: IRCChannel
	) {
		noteTypingState(state, fromNickname: nickname, in: channel, at: Date())
	}

	@objc(noteTypingState:fromNickname:inChannel:atDate:)
	public func noteTypingState(
		_ state: IRCTypingState,
		fromNickname nickname: String,
		in channel: IRCChannel,
		at date: Date
	) {
		guard nickname.isEmpty == false else {
			return
		}

		let channelKey = channel.uniqueIdentifier
		let nicknameKey = nickname.lowercased()
		var channelEntries = entries[channelKey] ?? [:]
		let existingEntry = channelEntries[nicknameKey]
		var changed = false

		if state == .done {
			if existingEntry != nil {
				channelEntries.removeValue(forKey: nicknameKey)
				changed = true
			}
		} else if let existingEntry {
			changed = existingEntry.state != state
			existingEntry.state = state
			existingEntry.updatedAt = date
		} else {
			sequence += 1
			channelEntries[nicknameKey] = TypingEntry(
				nickname: nickname,
				sequence: sequence,
				state: state,
				updatedAt: date
			)
			channels.setObject(channel, forKey: channelKey as NSString)
			changed = true
		}

		if channelEntries.isEmpty {
			entries.removeValue(forKey: channelKey)
			channels.removeObject(forKey: channelKey as NSString)
		} else {
			entries[channelKey] = channelEntries
		}

		scheduleExpiry()

		if changed {
			postChange(for: channel)
		}
	}

	@objc(removeNickname:)
	public func removeNickname(_ nickname: String) {
		let nicknameKey = nickname.lowercased()

		for channelKey in Array(entries.keys) {
			guard var channelEntries = entries[channelKey], channelEntries.removeValue(forKey: nicknameKey) != nil
			else {
				continue
			}

			let channel = channels.object(forKey: channelKey as NSString)

			if channelEntries.isEmpty {
				entries.removeValue(forKey: channelKey)
				channels.removeObject(forKey: channelKey as NSString)
			} else {
				entries[channelKey] = channelEntries
			}

			if let channel {
				postChange(for: channel)
			}
		}
	}

	@objc(removeAllInChannel:)
	public func removeAll(in channel: IRCChannel) {
		let channelKey = channel.uniqueIdentifier

		guard entries.removeValue(forKey: channelKey) != nil else {
			return
		}

		channels.removeObject(forKey: channelKey as NSString)
		postChange(for: channel)
	}

	@objc public func removeAll() {
		let channelKeys = Array(entries.keys)

		entries.removeAll()

		for channelKey in channelKeys {
			if let channel = channels.object(forKey: channelKey as NSString) {
				postChange(for: channel)
			}
		}

		channels.removeAllObjects()
		expiryTimer?.invalidate()
		expiryTimer = nil
	}

	@objc(typingNicknamesInChannel:)
	public func typingNicknames(in channel: IRCChannel) -> [String] {
		typingNicknames(in: channel, at: Date())
	}

	@objc(typingNicknamesInChannel:atDate:)
	public func typingNicknames(in channel: IRCChannel, at date: Date) -> [String] {
		guard let channelEntries = entries[channel.uniqueIdentifier] else {
			return []
		}

		return channelEntries.values
			.filter { $0.expiresAt >= date }
			.sorted { $0.sequence < $1.sequence }
			.map(\.nickname)
	}

	@objc(expireEntriesAtDate:)
	public func expireEntries(at date: Date) {
		for channelKey in Array(entries.keys) {
			guard var channelEntries = entries[channelKey] else {
				continue
			}

			let oldCount = channelEntries.count
			channelEntries = channelEntries.filter { $0.value.expiresAt >= date }
			let changed = channelEntries.count != oldCount
			let channel = channels.object(forKey: channelKey as NSString)

			if channelEntries.isEmpty {
				entries.removeValue(forKey: channelKey)
				channels.removeObject(forKey: channelKey as NSString)
			} else {
				entries[channelKey] = channelEntries
			}

			if changed, let channel {
				postChange(for: channel)
			}
		}

		scheduleExpiry()
	}

	private func scheduleExpiry() {
		guard entries.isEmpty == false else {
			expiryTimer?.invalidate()
			expiryTimer = nil
			return
		}

		guard expiryTimer == nil else {
			return
		}

		expiryTimer = Timer.scheduledTimer(
			timeInterval: 1.0,
			target: timerTarget,
			selector: #selector(TypingTimerTarget.timerFired(_:)),
			userInfo: nil,
			repeats: true
		)
		expiryTimer?.tolerance = 0.2
	}

	private func postChange(for channel: IRCChannel) {
		guard let client else {
			return
		}

		NotificationCenter.default.post(
			name: .IRCTypingTrackerDidChange,
			object: client,
			userInfo: [IRCTypingTrackerChannelKey: channel]
		)
	}
}
