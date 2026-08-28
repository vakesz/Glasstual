/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

public extension IRCClient {
	@objc var myself: User? {
		findUser(userNickname)
	}

	@objc(userExists:)
	func userExists(_ nickname: String) -> Bool {
		findUser(nickname) != nil
	}

	@objc(findUser:)
	func findUser(_ nickname: String) -> User? {
		usersByNickname[casefoldNickname(nickname)]
	}

	@objc internal func rekeyUserList() {
		usersByNickname = Dictionary(
			usersByNickname.values.map { (casefoldNickname($0.nickname), $0) },
			uniquingKeysWith: { _, latest in latest }
		)
	}

	@objc(mutableCopyOfUserWithNickname:)
	internal func mutableCopyOfUser(withNickname nickname: String) -> UserMutable {
		guard let user = findUser(nickname) else {
			return UserMutable(nickname: nickname, on: self)
		}

		guard let mutableUser = user.mutableCopy() as? UserMutable else {
			preconditionFailure("IRCUser mutable copies must use IRCUserMutable")
		}
		return mutableUser
	}

	@objc var numberOfUsers: UInt {
		UInt(usersByNickname.count)
	}

	@objc var userList: [User] {
		Array(usersByNickname.values)
	}

	@objc(addUser:)
	func add(_ user: User) {
		_ = addAndReturn(user)
	}

	@objc(addUserAndReturn:)
	internal func addAndReturn(_ user: User) -> User {
		let storedUser: User
		if user is UserMutable {
			guard let immutableUser = user.copy() as? User else {
				preconditionFailure("IRCUserMutable copies must use IRCUser")
			}
			storedUser = immutableUser
		} else {
			storedUser = user
		}

		usersByNickname[casefoldNickname(storedUser.nickname)] = storedUser
		storedUser.becamePrimaryUser()
		return storedUser
	}

	@objc(findUserOrCreate:)
	func findUserOrCreate(_ nickname: String) -> User {
		if let user = findUser(nickname) {
			return user
		}

		let user = User(nickname: nickname, on: self)
		add(user)
		return user
	}

	@objc(removeUser:)
	func remove(_ user: User) {
		user.cancelRemoveUserTimer()
		if let hostmask = user.hostmask {
			clearAddressBookCache(forHostmask: hostmask)
		}
		removeUser(withNickname: user.nickname)
	}

	@objc(removeUserWithNickname:)
	func removeUser(withNickname nickname: String) {
		usersByNickname.removeValue(forKey: casefoldNickname(nickname))
	}

	@objc internal func removeAllUsers() {
		usersByNickname.removeAll()
	}

	@objc(renameUser:to:)
	internal func rename(_ user: User, to nickname: String) {
		modify(user) { $0.nickname = nickname }
	}

	@objc(renameUserWithNickname:to:)
	internal func renameUser(withNickname oldNickname: String, to newNickname: String) {
		guard let user = findUser(oldNickname) else { return }
		rename(user, to: newNickname)
	}

	@objc(modifyUser:withBlock:)
	internal func modify(_ user: User, block: (UserMutable) -> Void) {
		guard let mutableUser = user.mutableCopy() as? UserMutable else {
			preconditionFailure("IRCUser mutable copies must use IRCUserMutable")
		}

		block(mutableUser)
		if user.nickname != mutableUser.nickname {
			remove(user)
		}
		add(mutableUser)
	}

	@objc(modifyUserUserWithNickname:withBlock:)
	internal func modifyUser(withNickname nickname: String, block: (UserMutable) -> Void) {
		guard let user = findUser(nickname) else { return }
		modify(user, block: block)
	}
}

@MainActor
extension IRCClient {
	@objc(modifyUserWithNickname:asAway:)
	func modifyUser(withNickname nickname: String, asAway away: Bool) {
		guard let user = findUser(nickname) else { return }
		modify(user, asAway: away)
	}

	@objc(modifyUser:asAway:)
	func modify(_ user: User, asAway away: Bool) {
		guard monitorAwayStatus else { return }

		if away {
			user.markAsAway()
		} else {
			user.markAsReturned()
		}
		NSObject.applicationController().mainWindow?.updateDrawingForUserInUserList(user)
	}

	@objc func resetAwayStatusForUsers() {
		for user in userList {
			user.markAsReturned()
		}
	}
}
