// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension Notification.Name {
	static let TypingTrackerDidChange = Self("IRCTypingTrackerDidChangeNotification")
}

nonisolated let typingTrackerChannelKey = "channel"

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
	private weak var client: Client?

	private var entries: [String: [String: TypingEntry]] = [:]
	private let channels = NSMapTable<NSString, Channel>.strongToWeakObjects()
	/// Drops the indicators whose timeout has passed, for as long as there is
	/// one to drop.
	private lazy var expiryTimer = ClientTimer { [weak self] _ in
		self?.expireEntries(at: Date())
	}

	private var sequence: UInt = 0

	init(client: Client) {
		self.client = client
	}

	/// The state a `+typing` tag stands for. An unknown value is read as
	/// `done`, which is what clears the indicator rather than leaving it up.
	static func state(forTagValue value: String?) -> TypingState {
		value.flatMap(TypingState.init(rawValue:)) ?? .done
	}

	func noteTypingState(
		_ state: TypingState,
		fromNickname nickname: String,
		in channel: Channel
	) {
		noteTypingState(state, fromNickname: nickname, in: channel, at: Date())
	}

	func noteTypingState(
		_ state: TypingState,
		fromNickname nickname: String,
		in channel: Channel,
		at date: Date
	) {
		guard nickname.isEmpty == false else {
			return
		}

		let channelKey = channel.uniqueIdentifier
		let nicknameKey = casefolded(nickname)
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

	func removeNickname(_ nickname: String) {
		let nicknameKey = casefolded(nickname)

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

	/** The key a nickname is filed under.

	 The server decides what two spellings of a nickname are the same one:
	 under RFC 1459 `nick[home]` and `nick{home}` are, and `lowercased()` says
	 they are not while also folding non-ASCII letters no server folds. A
	 typing indicator filed under one spelling then never cleared when the
	 `done` tag arrived spelled the other way. */
	private func casefolded(_ nickname: String) -> String {
		client?.casefoldNickname(nickname) ?? nickname.lowercased()
	}

	func removeAll(in channel: Channel) {
		let channelKey = channel.uniqueIdentifier

		guard entries.removeValue(forKey: channelKey) != nil else {
			return
		}

		channels.removeObject(forKey: channelKey as NSString)
		postChange(for: channel)
	}

	func removeAll() {
		let channelKeys = Array(entries.keys)

		entries.removeAll()

		for channelKey in channelKeys {
			if let channel = channels.object(forKey: channelKey as NSString) {
				postChange(for: channel)
			}
		}

		channels.removeAllObjects()
		expiryTimer.stop()
	}

	func typingNicknames(in channel: Channel) -> [String] {
		typingNicknames(in: channel, at: Date())
	}

	func typingNicknames(in channel: Channel, at date: Date) -> [String] {
		guard let channelEntries = entries[channel.uniqueIdentifier] else {
			return []
		}

		return channelEntries.values
			.filter { $0.expiresAt >= date }
			.sorted { $0.sequence < $1.sequence }
			.map(\.nickname)
	}

	func expireEntries(at date: Date) {
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
			expiryTimer.stop()
			return
		}

		expiryTimer.startIfIdle(1.0, repeats: true)
	}

	private func postChange(for channel: Channel) {
		guard let client else {
			return
		}

		NotificationCenter.default.post(
			name: .TypingTrackerDidChange,
			object: client,
			userInfo: [typingTrackerChannelKey: channel]
		)
	}
}
