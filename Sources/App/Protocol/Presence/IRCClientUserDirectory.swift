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

/// How long a user with no channels in common is kept before it is reaped.
private nonisolated let removeUserTimerInterval: TimeInterval = 60 * 5 // nonisolated: let

/// How often the same away user's RPL_AWAY (301) may be shown.
private nonisolated let presentAwayMessageFor301Threshold: CFAbsoluteTime = 300.0 // nonisolated: let

public extension IRCClient {
	var myself: User? {
		findUser(userNickname)
	}

	func userExists(_ nickname: String) -> Bool {
		findUser(nickname) != nil
	}

	func findUser(_ nickname: String) -> User? {
		usersByNickname[casefoldNickname(nickname)]
	}

	internal func rekeyUserList() {
		usersByNickname = Dictionary(
			usersByNickname.values.map { (casefoldNickname($0.nickname), $0) },
			uniquingKeysWith: { _, latest in latest }
		)
	}

	/// An editable stand-in for `nickname`: a copy of the stored user, or a
	/// fresh one when the directory has never seen the nickname.
	internal func draftUser(withNickname nickname: String) -> User {
		findUser(nickname) ?? User(nickname: nickname)
	}

	var numberOfUsers: UInt {
		UInt(usersByNickname.count)
	}

	var userList: [User] {
		Array(usersByNickname.values)
	}

	func add(_ user: User) {
		_ = addAndReturn(user)
	}

	@discardableResult
	internal func addAndReturn(_ user: User) -> User {
		usersByNickname[casefoldNickname(user.nickname)] = user
		becamePrimaryUser(user)
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
		usersByNickname.removeValue(forKey: casefoldNickname(nickname))
	}

	internal func removeAllUsers() {
		for store in userStores.values {
			store.cancelRemoveUserTimer()
		}
		userStores.removeAll()
		usersByNickname.removeAll()
	}

	internal func rename(_ user: User, to nickname: String) {
		modify(user) { $0.nickname = nickname }
	}

	internal func renameUser(withNickname oldNickname: String, to newNickname: String) {
		guard let user = findUser(oldNickname) else { return }
		rename(user, to: newNickname)
	}

	/// Edits a copy of `user` and stores the result under its new nickname.
	internal func modify(_ user: User, block: (inout User) -> Void) {
		var editedUser = user

		block(&editedUser)
		if user.nickname != editedUser.nickname {
			removeUser(withNickname: user.nickname)
		}
		add(editedUser)
	}

	internal func modifyUser(withNickname nickname: String, block: (inout User) -> Void) {
		guard let user = findUser(nickname) else { return }
		modify(user, block: block)
	}

	/// The ban mask for `user` in this client's configured format.
	func banMask(for user: User) -> String {
		user.banMask(format: environment.preferences.banFormat)
	}
}

// MARK: - Per-person state

@MainActor
extension IRCClient {
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
	func relations(of user: User) -> [(channel: IRCChannel, member: ChannelUser)] {
		persistentStore(for: user).relations.relatedChannels.compactMap { channel in
			guard let member = channel.memberInfo?.findMember(withUserID: user.id) else {
				return nil
			}
			return (channel, member)
		}
	}

	/// `user`'s member in `channel`, if they are in it.
	func userAssociated(_ user: User, with channel: IRCChannel) -> ChannelUser? {
		guard persistentStore(for: user).relations.isAssociated(with: channel) else {
			return nil
		}

		return channel.memberInfo?.findMember(withUserID: user.id)
	}

	func associate(_ user: User, with channel: IRCChannel) {
		persistentStore(for: user).relations.associate(with: channel)
		toggleRemoveUserTimer(for: user)
	}

	func disassociate(_ user: User, from channel: IRCChannel) {
		persistentStore(for: user).relations.disassociate(from: channel)
		toggleRemoveUserTimer(for: user)
	}

	/** Whether the RPL_AWAY (301) reply for `user` should be shown, taking the
	 slot when it is.

	 A server repeats 301 for every message sent to an away user, so it is rate
	 limited. Asking is what opens the next window, which is why this is a
	 method: it used to read as a property and quietly moved the clock on every
	 access. */
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
		for channel in persistentStore(for: user).relations.relatedChannels {
			channel.memberInfo?.updateMember(withUserID: user.id) { $0.changeUser(to: user) }
		}
	}

	/// The directory has taken `user` as the stored copy of that person.
	func becamePrimaryUser(_ user: User) {
		updateRemoveUserTimerBlockToFire(for: user)
		relinkRelations(for: user)
	}

	// MARK: Remove-user timer

	private func updateRemoveUserTimerBlockToFire(for user: User) {
		guard let removeUserTimer = userStores[user.id]?.removeUserTimer else {
			return
		}

		removeUserTimer.setEventHandler(handler: removeUserTimerBlockToFire(for: user))
	}

	private func toggleRemoveUserTimer(for user: User) {
		if persistentStore(for: user).relations.numberOfRelations > 0 {
			cancelRemoveUserTimer(for: user)
		} else {
			startRemoveUserTimer(for: user)
		}
	}

	private func startRemoveUserTimer(for user: User) {
		let store = persistentStore(for: user)

		if store.removeUserTimer != nil {
			return
		}

		let removeUserTimer = DispatchSource.makeTimerSource(queue: .main)
		removeUserTimer.schedule(deadline: .now() + removeUserTimerInterval)
		removeUserTimer.setEventHandler(handler: removeUserTimerBlockToFire(for: user))
		store.removeUserTimer = removeUserTimer
		removeUserTimer.activate()
	}

	func cancelRemoveUserTimer(for user: User) {
		userStores[user.id]?.cancelRemoveUserTimer()
	}

	private func removeUserTimerBlockToFire(for user: User) -> @Sendable () -> Void {
		let nickname = user.nickname

		/* The timer fires off the main actor, so the handler carries the
		 nickname and looks the user up again on the way in. */
		return { [weak self] in
			Task { @MainActor [weak self] in
				guard let self, let user = findUser(nickname) else {
					return
				}

				remove(user)
			}
		}
	}
}

@MainActor
extension IRCClient {
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
		output?.updateDrawingForUser(updated)
	}

	func resetAwayStatusForUsers() {
		for user in userList {
			modify(user) { $0.markAsReturned() }
		}
	}
}
