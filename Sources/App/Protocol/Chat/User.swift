// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** Someone visible to this client.

 A value. `id` is the person: it is minted once, when the client first sees the
 nickname, and travels through every edit and every rename, so a copy taken to
 be edited and handed back to the directory still names the same person. The
 state that belongs to the person rather than to this snapshot of them -- which
 channels they are in, the away-message clock, the removal timer -- lives in the
 client's `UserPersistentStore` for that `id`.

 Editing means taking a copy, editing that, and handing it back to the directory
 (`Client.modify(_:block:)`), which relinks the channels the person is in. */
nonisolated struct User: Identifiable, Hashable, Sendable, CustomStringConvertible {
	/// The person, stable across renames and edits.
	let id: UUID

	var nickname: String
	var username: String?
	var address: String?
	var realName: String?
	var account: String?
	var isAway = false
	var isIRCop = false
	var isBot = false

	init(nickname: String) {
		id = UUID()
		self.nickname = nickname
	}

	/// A user with a caller-supplied identity. Only the directory and its tests
	/// pick an `id`; everyone else takes a copy of an existing user.
	init(id: UUID, nickname: String) {
		self.id = id
		self.nickname = nickname
	}

	var hostmaskFragment: String? {
		guard let username, let address else {
			return nil
		}

		return "\(username)@\(address)"
	}

	var hostmask: String? {
		guard let username, let address else {
			return nil
		}

		return "\(nickname)!\(username)@\(address)"
	}

	/// The ban mask the preference asks for. The format is passed in because a
	/// user does not know its client; `Client.banMask(for:)` reads it.
	func banMask(format: HostmaskBanFormat) -> String {
		guard let username, let address else {
			return "\(nickname)!*@*"
		}

		switch format {
		case .whnin:
			return "*!*@\(address)"
		case .whainn:
			return "*!\(username)@\(address)"
		case .whanni:
			return "\(nickname)!*@\(address)"
		case .exact:
			return "\(nickname)!\(username)@\(address)"
		@unknown default:
			return "\(nickname)!*@*"
		}
	}

	mutating func markAsAway() {
		isAway = true
	}

	mutating func markAsReturned() {
		isAway = false
	}

	var description: String {
		"<User \(nickname)>"
	}
}

/** The state that belongs to a person rather than to one ``User`` value.

 A `User` is a value, so a copy taken to be edited would copy this too. The
 client keeps one store per `User.ID` and hands it out by identity, which is
 what makes the removal timer and the away-message clock survive an edit, and
 keeps a throwaway copy from retiring the live person's timer. */
@MainActor
final class UserPersistentStore {
	/// The channels the person is in. The member itself lives in each channel's
	/// member list; this records only where to look.
	var relatedChannels: Set<Channel> = []

	var presentAwayMessageFor301LastEvent: CFAbsoluteTime = 0

	/// Retires the person once they have been in no channel for long enough.
	var removeUserTask: Task<Void, Never>?

	/// Stops the removal timer. The client calls it when it drops the store;
	/// a `deinit` cannot, because the task is main-actor state.
	func cancelRemoveUserTimer() {
		removeUserTask?.cancel()
		removeUserTask = nil
	}
}
