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

import CocoaExtensions
import Foundation
import os

private nonisolated let removeUserTimerInterval: TimeInterval = 60 * 5
private nonisolated let presentAwayMessageFor301Threshold: CFAbsoluteTime = 300.0

private let userLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCUser"
)

/** Someone visible to this client, identified by object identity: the user
 directory and every member list hold the same instance.

 Changing a user means taking a `duplicate()`, editing that, and handing it back
 to the directory, which relinks the relations. Editing an instance the
 directory already holds is what the setters' `internal` access guards against. */
@objc(IRCUser)
public final nonisolated class User: NSObject {
	/// `nil` once the client has been torn down. Users routinely outlive
	/// their client through the shared persistent store and the removal
	/// timer, so this must not be force-unwrapped.
	public private(set) weak var client: IRCClient?

	private var persistentStore = UserPersistentStore()

	public internal(set) var nickname = ""
	public internal(set) var username: String?
	public internal(set) var address: String?
	public internal(set) var realName: String?
	public internal(set) var account: String?
	public internal(set) var isAway = false
	public internal(set) var isIRCop = false
	public internal(set) var isBot = false

	/** The relation map is keyed by channel and reads the channel's kind, so it
	 and everything that reaches it live on the main actor. */
	@MainActor
	private var relationsInt: UserRelations {
		if let relations = persistentStore.relations {
			return relations
		}

		let relations = UserRelations()
		persistentStore.relations = relations
		return relations
	}

	public var hostmaskFragment: String? {
		guard let username, let address else {
			return nil
		}

		return "\(username)@\(address)"
	}

	public var hostmask: String? {
		guard let username, let address else {
			return nil
		}

		return "\(nickname)!\(username)@\(address)"
	}

	public var banMask: String {
		guard let username, let address else {
			return "\(nickname)!*@*"
		}

		switch client?.environment.preferences.banFormat ?? ClientPreferences().banFormat {
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

	public var lowercaseNickname: String {
		nickname.lowercased()
	}

	public var uppercaseNickname: String {
		nickname.uppercased()
	}

	/// Whether the RPL_AWAY (301) reply for this user should be shown, taking
	/// the slot when it is.
	///
	/// A server repeats 301 for every message sent to an away user, so it is
	/// rate limited. Asking is what opens the next window, which is why this
	/// is a method: it used to read as a property and quietly moved the clock
	/// on every access.
	public func claimAwayMessagePresentation() -> Bool {
		let now = CFAbsoluteTimeGetCurrent()

		guard (persistentStore.presentAwayMessageFor301LastEvent + presentAwayMessageFor301Threshold) < now else {
			return false
		}

		persistentStore.presentAwayMessageFor301LastEvent = now

		return true
	}

	@MainActor public var relations: [IRCChannel: ChannelUser] {
		relationsInt.relations
	}

	@MainActor
	public init(nickname: String, on client: IRCClient) {
		self.nickname = nickname
		self.client = client

		super.init()

		persistentStore.relations = UserRelations()
	}

	/** Shares the persistent store — the removal timer, the relation map and the
	 away-message clock belong to the person, not to this snapshot of them. */
	private init(copying other: User) {
		client = other.client
		persistentStore = other.persistentStore
		nickname = other.nickname
		username = other.username
		address = other.address
		realName = other.realName
		account = other.account
		isAway = other.isAway
		isIRCop = other.isIRCop
		isBot = other.isBot

		super.init()
	}

	/// An editable copy. The directory stores whichever instance it is handed,
	/// so edit the duplicate and add it back rather than editing a stored user.
	public func duplicate() -> User {
		User(copying: self)
	}

	public func markAsAway() {
		isAway = true
	}

	public func markAsReturned() {
		isAway = false
	}

	override public var description: String {
		"<IRCUser \(nickname)>"
	}

	override public func isEqual(_ object: Any?) -> Bool {
		guard let object else {
			return false
		}

		if object as AnyObject === self {
			return true
		}

		guard let other = object as? User else {
			return false
		}

		return client === other.client
			&& nickname == other.nickname
			&& username == other.username
			&& address == other.address
			&& realName == other.realName
			&& account == other.account
			&& isAway == other.isAway
			&& isIRCop == other.isIRCop
			&& isBot == other.isBot
	}

	/** `isEqual` compares values, so `hash` has to as well: inheriting the identity
	 hash makes equal-but-distinct users behave incorrectly in sets and dictionaries. */
	override public var hash: Int {
		var hasher = Hasher()
		hasher.combine(client.map(ObjectIdentifier.init))
		hasher.combine(nickname)
		hasher.combine(username)
		hasher.combine(address)
		hasher.combine(realName)
		hasher.combine(account)
		hasher.combine(isAway)
		hasher.combine(isIRCop)
		hasher.combine(isBot)
		return hasher.finalize()
	}

	// MARK: - Remove-user timer

	private func updateRemoveUserTimerBlockToFire() {
		guard let removeUserTimer = persistentStore.removeUserTimer else {
			return
		}

		removeUserTimer.setEventHandler(handler: removeUserTimerBlockToFire())
	}

	@MainActor
	private func toggleRemoveUserTimer() {
		if relationsInt.numberOfRelations > 0 {
			cancelRemoveUserTimer()
		} else {
			startRemoveUserTimer()
		}
	}

	private func startRemoveUserTimer() {
		if persistentStore.removeUserTimer != nil {
			return
		}

		let removeUserTimer = DispatchSource.makeTimerSource(queue: .main)
		removeUserTimer.schedule(deadline: .now() + removeUserTimerInterval)
		removeUserTimer.setEventHandler(handler: removeUserTimerBlockToFire())
		persistentStore.removeUserTimer = removeUserTimer
		removeUserTimer.activate()
	}

	public func cancelRemoveUserTimer() {
		guard let removeUserTimer = persistentStore.removeUserTimer else {
			return
		}

		removeUserTimer.cancel()
		persistentStore.removeUserTimer = nil
	}

	private func removeUserTimerBlockToFire() -> () -> Void {
		weak let client = client
		let nickname = nickname

		/* The timer fires off the main actor and a user is not `Sendable`, so the
		 handler carries the nickname and looks the user up again on the way in. */
		return {
			Task { @MainActor [weak client] in
				guard let client, let user = client.findUser(nickname) else {
					return
				}

				client.remove(user)
			}
		}
	}

	// MARK: - Relations

	@MainActor
	public func associate(_ user: ChannelUser, with channel: IRCChannel) {
		relationsInt.associate(user, with: channel)
		toggleRemoveUserTimer()
	}

	@MainActor
	public func disassociateUser(with channel: IRCChannel) {
		relationsInt.disassociateUser(with: channel)
		toggleRemoveUserTimer()
	}

	@MainActor
	public func userAssociated(with channel: IRCChannel) -> ChannelUser? {
		relationsInt.userAssociated(with: channel)
	}

	@MainActor
	public func relinkRelations() {
		for relatedUser in relationsInt.relatedUsers {
			relatedUser.changeUser(to: self)
		}
	}

	@MainActor
	public func becamePrimaryUser() {
		updateRemoveUserTimerBlockToFire()
		relinkRelations()
	}

	@MainActor
	public func enumerateRelations(
		_ block: (IRCChannel, ChannelUser, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		relationsInt.enumerateRelations(block)
	}
}
