// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// How long a user with no channels in common is kept before it is reaped.
private nonisolated let removeUserTimerInterval: TimeInterval = 60 * 5

/// How often the same away user's RPL_AWAY (301) may be shown.
private nonisolated let presentAwayMessageFor301Threshold: CFAbsoluteTime = 300.0

extension ServerSession {
	var myself: User? {
		findUser(userNickname)
	}

	func findUser(_ nickname: String) -> User? {
		userIndex[foldedName: casefoldNickname(nickname)]
	}

	/** Refiles the directory under the casemapping the server advertises now.

	 A mapping can merge two keys that were distinct — `nick[home]` and
	 `nick{home}` are one person under RFC 1459 and two under `ascii` — and the
	 loser has to leave the channels too. Member rows are keyed by person, so a
	 row left behind is one nothing can find, replace or remove again. Which of
	 the two loses is decided by nickname, so the same 005 always produces the
	 same directory. */
	func rekeyUserList() {
		trackedUsers.caseMapping = supportInfo.caseMapping

		for user in userIndex.rekeyed(by: casefoldNickname, naming: \.nickname) {
			discardDisplacedUser(user)
		}
	}

	/// Takes a user the rekey could not keep out of every channel it was in.
	/// `remove(_:)` is not what this wants: it would delete the directory entry
	/// the winner now holds under the same folded nickname.
	private func discardDisplacedUser(_ user: User) {
		for (channel, member) in relations(of: user) {
			channel.memberInfo?.removeMember(member)
		}

		cancelRemoveUserTimer(for: user)

		if let hostmask = user.hostmask {
			clearAddressBookCache(forHostmask: hostmask)
		}

		userStores.removeValue(forKey: user.id)
	}

	/// An editable stand-in for `nickname`: a copy of the stored user, or a
	/// fresh one when the directory has never seen the nickname.
	func draftUser(withNickname nickname: String) -> User {
		findUser(nickname) ?? User(nickname: nickname)
	}

	var numberOfUsers: UInt {
		UInt(userIndex.count)
	}

	var userList: [User] {
		Array(userIndex.values)
	}

	func add(_ user: User) {
		_ = addAndReturn(user)
	}

	@discardableResult
	func addAndReturn(_ user: User) -> User {
		userIndex[foldedName: casefoldNickname(user.nickname)] = user
		relinkRelations(for: user)
		return user
	}

	func findUserOrCreate(_ nickname: String) -> User {
		if let user = findUser(nickname) {
			return user
		}

		let user = User(nickname: nickname)
		add(user)
		return user
	}

	func remove(_ user: User) {
		cancelRemoveUserTimer(for: user)
		if let hostmask = user.hostmask {
			clearAddressBookCache(forHostmask: hostmask)
		}
		userStores.removeValue(forKey: user.id)
		removeUser(withNickname: user.nickname)
	}

	func removeUser(withNickname nickname: String) {
		userIndex.removeValue(forFoldedName: casefoldNickname(nickname))
	}

	func removeAllUsers() {
		for store in userStores.values {
			store.cancelRemoveUserTimer()
		}
		userStores.removeAll()
		userIndex.removeAll()
	}

	func rename(_ user: User, to nickname: String) {
		modify(user) { $0.nickname = nickname }
	}

	func renameUser(withNickname oldNickname: String, to newNickname: String) {
		guard let user = findUser(oldNickname) else { return }
		rename(user, to: newNickname)
	}

	/** Edits a copy of `user` and stores the result under its new nickname.

	 A rename drops the old key and the address-book match cached against the
	 old hostmask, but keeps the person: their store is keyed by identity, so
	 the channels they are in and their removal timer survive the rename. */
	func modify(_ user: User, block: (inout User) -> Void) {
		var editedUser = user

		block(&editedUser)

		if user.nickname != editedUser.nickname {
			if let hostmask = user.hostmask {
				clearAddressBookCache(forHostmask: hostmask)
			}

			removeUser(withNickname: user.nickname)
		}

		add(editedUser)
	}

	func modifyUser(withNickname nickname: String, block: (inout User) -> Void) {
		guard let user = findUser(nickname) else { return }
		modify(user, block: block)
	}

	/// The ban mask for `user` in this session's configured format.
	func banMask(for user: User) -> String {
		user.banMask(format: environment.settings.banFormat)
	}
}

// MARK: - Per-person state

@MainActor
extension ServerSession {
	/// The store for `user`, created on first use.
	private func persistentStore(for user: User) -> UserPersistentStore {
		if let store = userStores[user.id] {
			return store
		}

		let store = UserPersistentStore()
		userStores[user.id] = store
		return store
	}

	/// The channels `user` is in, paired with their member in each.
	func relations(of user: User) -> [(channel: Conversation, member: Member)] {
		persistentStore(for: user).relatedChannels.compactMap { channel in
			guard let member = channel.memberInfo?.findMember(withUserID: user.id) else {
				return nil
			}
			return (channel, member)
		}
	}

	/// `user`'s member in `channel`, if they are in it.
	func userAssociated(_ user: User, with channel: Conversation) -> Member? {
		guard persistentStore(for: user).relatedChannels.contains(channel) else {
			return nil
		}

		return channel.memberInfo?.findMember(withUserID: user.id)
	}

	/// A direct conversation is not a shared room, so it is not a relation: only
	/// a channel keeps a person in the directory.
	func associate(_ user: User, with channel: Conversation) {
		guard channel.isChannel else { return }

		persistentStore(for: user).relatedChannels.insert(channel)
		toggleRemoveUserTimer(for: user)
	}

	func disassociate(_ user: User, from channel: Conversation) {
		persistentStore(for: user).relatedChannels.remove(channel)
		toggleRemoveUserTimer(for: user)
	}

	/** Whether the RPL_AWAY (301) reply for `user` should be shown, taking the
	 slot when it is.

	 A server repeats 301 for every message sent to an away user, so it is rate
	 limited. Asking is what opens the next window, which is why this is a method
	 rather than a property: reading it moves the clock. */
	func claimAwayMessagePresentation(for user: User) -> Bool {
		let store = persistentStore(for: user)
		let now = CFAbsoluteTimeGetCurrent()

		guard (store.presentAwayMessageFor301LastEvent + presentAwayMessageFor301Threshold) < now else {
			return false
		}

		store.presentAwayMessageFor301LastEvent = now

		return true
	}

	/// Writes `user` into the member every channel it is in holds for it, so a
	/// rename or an edit reaches the member lists.
	func relinkRelations(for user: User) {
		for channel in persistentStore(for: user).relatedChannels {
			channel.memberInfo?.updateMember(withUserID: user.id) { $0.changeUser(to: user) }
		}
	}

	// MARK: Remove-user timer

	private func toggleRemoveUserTimer(for user: User) {
		if persistentStore(for: user).relatedChannels.isEmpty == false {
			cancelRemoveUserTimer(for: user)
		} else {
			startRemoveUserTimer(for: user)
		}
	}

	private func startRemoveUserTimer(for user: User) {
		let store = persistentStore(for: user)

		guard store.removeUserTask == nil else {
			return
		}

		/* The person is identified by `User.ID` rather than by the value that
		 started the timer: a rename or an edit replaces that value, and the one
		 to retire is whichever the directory holds when the timer comes due. */
		let identifier = user.id

		store.removeUserTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(removeUserTimerInterval))

			guard Task.isCancelled == false, let self,
			      let user = userList.first(where: { $0.id == identifier })
			else {
				return
			}

			remove(user)
		}
	}

	func cancelRemoveUserTimer(for user: User) {
		userStores[user.id]?.cancelRemoveUserTimer()
	}
}

@MainActor
extension ServerSession {
	func modifyUser(withNickname nickname: String, asAway away: Bool) {
		guard let user = findUser(nickname) else { return }
		modify(user, asAway: away)
	}

	func modify(_ user: User, asAway away: Bool) {
		guard monitorAwayStatus else { return }

		modify(user) { edited in
			if away {
				edited.markAsAway()
			} else {
				edited.markAsReturned()
			}
		}

		guard let updated = findUser(user.nickname) else { return }
		output?.updateDrawingForUserInUserList(updated)
	}

	func resetAwayStatusForUsers() {
		for user in userList {
			modify(user) { $0.markAsReturned() }
		}
	}
}
