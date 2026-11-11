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
			handDirectConversation(named: user.nickname)
		}
	}

	/** Takes a user that lost its folded nickname to another person out of
	 every conversation it was in: the rekey's loser, or the stale holder of a
	 nickname somebody was just renamed into.

	 `remove(_:)` is not what this wants: it would delete the directory entry
	 the winner now holds under the same folded nickname. The direct
	 conversation named after the user goes first, because removing its member
	 restarts the removal timer through `disassociate`, which has to happen
	 while the store is still there to be dropped. */
	private func discardDisplacedUser(_ user: User) {
		if let direct = directConversation(named: user.nickname),
		   let member = direct.memberInfo?.findMember(withUserID: user.id)
		{
			direct.memberInfo?.removeMember(member)
		}

		for (channel, member) in relations(of: user) {
			channel.memberInfo?.removeMember(member)
		}

		cancelRemoveUserTimer(for: user)

		if let hostmask = user.hostmask {
			clearAddressBookCache(forHostmask: hostmask)
		}

		userStores.removeValue(forKey: user.id)
	}

	/// Gives an open direct conversation named `nickname` a member for whoever
	/// holds that nickname now, once its previous holder has been discarded.
	/// The conversation is the one the user has been reading under that name, so
	/// it follows the nickname rather than the person who left it.
	private func handDirectConversation(named nickname: String) {
		guard let direct = directConversation(named: nickname), let members = direct.memberInfo,
		      let holder = findUser(nickname), members.findMember(withUserID: holder.id) == nil
		else { return }

		direct.addUser(holder)
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
	 the channels they are in and their removal timer survive the rename.

	 A rename into a nickname the directory still files under somebody else —
	 a person who changed nick out of sight and was never reaped — retires that
	 person first, as a rekey does. A rename that only changes case finds the
	 renamed person under the new key, and is no collision. */
	func modify(_ user: User, block: (inout User) -> Void) {
		var editedUser = user

		block(&editedUser)

		var displacedUser: User?
		if user.nickname != editedUser.nickname {
			if let hostmask = user.hostmask {
				clearAddressBookCache(forHostmask: hostmask)
			}

			removeUser(withNickname: user.nickname)

			if let holder = findUser(editedUser.nickname), holder.id != editedUser.id {
				displacedUser = holder
				discardDisplacedUser(holder)
			}
		}

		add(editedUser)

		if displacedUser != nil {
			handDirectConversation(named: editedUser.nickname)
		}
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

	/** A snapshot of the channels `user` is in, safe to walk while members leave.

	 The store keeps them as a set, whose order is random, so `ordered` puts them
	 in conversation-list order for callers that print into each one. Only
	 channels this session still lists and that still hold members are returned. */
	func relatedChannels(of user: User, ordered: Bool = true) -> [Conversation] {
		let related = persistentStore(for: user).relatedChannels
		guard related.isEmpty == false else { return [] }
		guard ordered, related.count > 1 else {
			return Array(related).filter { $0.associatedSession === self && $0.memberInfo != nil }
		}

		return conversationList.filter { related.contains($0) && $0.memberInfo != nil }
	}

	/// `user`'s member in `channel`, if they are in it.
	func userAssociated(_ user: User, with channel: Conversation) -> Member? {
		guard persistentStore(for: user).relatedChannels.contains(channel) else {
			return nil
		}

		return channel.memberInfo?.findMember(withUserID: user.id)
	}

	/** A direct conversation is not a shared room, so it is not a relation.

	 Opening one still holds its two people in the directory: closing it runs
	 `disassociate`, which starts the removal timer for anyone left with no
	 channel, and opening it again has to stop that timer, or the person is
	 reaped while the conversation is open. A later `disassociate` starts it
	 again. */
	func associate(_ user: User, with channel: Conversation) {
		guard channel.isChannel else {
			cancelRemoveUserTimer(for: user)
			return
		}

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
		let startingNickname = user.nickname
		let clock = userRemovalClock

		store.removeUserTask = Task { [weak self] in
			await clock.wait(removeUserTimerInterval)

			guard Task.isCancelled == false, let self else {
				return
			}

			removalTimerFired(for: identifier, startingNickname: startingNickname)
		}
	}

	/** Retires the person a removal timer was started for, unless something
	 outside the channels still holds them.

	 The slot is cleared first, so a timer that came due without reaping leaves
	 room for the next `disassociate` to start another. A person the directory
	 no longer holds — renamed over, or already removed — leaves only the store,
	 which is dropped here rather than kept for good. */
	private func removalTimerFired(for identifier: User.ID, startingNickname: String) {
		userStores[identifier]?.removeUserTask = nil

		guard let user = storedUser(withID: identifier, startingNickname: startingNickname) else {
			userStores.removeValue(forKey: identifier)
			return
		}

		guard isHeldOutsideChannels(user) == false else {
			return
		}

		remove(user)
	}

	/// The local user, whom `myself` has to keep finding, and the peer of an
	/// open direct conversation, whose member row is found through the directory.
	private func isHeldOutsideChannels(_ user: User) -> Bool {
		if nicknameIsMyself(user.nickname) {
			return true
		}

		return directConversation(named: user.nickname)?.memberInfo?.findMember(withUserID: user.id) != nil
	}

	/** The directory's user for `identifier`. The nickname the timer started with
	 is still right unless the person was renamed, so one hashed lookup answers
	 nearly every time; only a rename falls back to walking the directory, and
	 that walk does not copy it. */
	private func storedUser(withID identifier: User.ID, startingNickname: String) -> User? {
		if let user = findUser(startingNickname), user.id == identifier {
			return user
		}
		return userIndex.values.first { $0.id == identifier }
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
