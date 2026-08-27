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

import CocoaExtensions
import Foundation
import os

private let removeUserTimerInterval: TimeInterval = 60 * 5
private let presentAwayMessageFor301Threshold: CFAbsoluteTime = 300.0

private let userLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCUser"
)

@objc(IRCUser)
open class User: PortablePropertyObject {
	fileprivate weak var clientStorage: IRCClient?
	fileprivate var persistentStore = UserPersistentStore()

	fileprivate var nicknameStorage = ""
	fileprivate var usernameStorage: String?
	fileprivate var addressStorage: String?
	fileprivate var realNameStorage: String?
	fileprivate var accountStorage: String?
	fileprivate var isAwayStorage = false
	fileprivate var isIRCopStorage = false
	fileprivate var isBotStorage = false

	private var relationsInt: UserRelations {
		if let relations = persistentStore.relations {
			return relations
		}

		let relations = UserRelations()
		persistentStore.relations = relations
		return relations
	}

	@objc public var client: IRCClient {
		clientStorage!
	}

	@objc public var nickname: String {
		nicknameStorage
	}

	@objc public var username: String? {
		usernameStorage
	}

	@objc public var address: String? {
		addressStorage
	}

	@objc public var realName: String? {
		realNameStorage
	}

	@objc public var account: String? {
		accountStorage
	}

	@objc public var isAway: Bool {
		get { isAwayStorage }
		set {
			if isAwayStorage != newValue {
				isAwayStorage = newValue
			}
		}
	}

	@objc public var isIRCop: Bool {
		isIRCopStorage
	}

	@objc public var isBot: Bool {
		isBotStorage
	}

	@objc public var hostmaskFragment: String? {
		guard let username = usernameStorage, let address = addressStorage else {
			return nil
		}

		return "\(username)@\(address)"
	}

	@objc public var hostmask: String? {
		guard let username = usernameStorage, let address = addressStorage else {
			return nil
		}

		return "\(nicknameStorage)!\(username)@\(address)"
	}

	@objc public var banMask: String {
		let nickname = nicknameStorage

		guard let username = usernameStorage, let address = addressStorage else {
			return "\(nickname)!*@*"
		}

		switch TextualPreferences.banFormat() {
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

	@objc public var lowercaseNickname: String {
		nicknameStorage.lowercased()
	}

	@objc public var uppercaseNickname: String {
		nicknameStorage.uppercased()
	}

	@objc public var presentAwayMessageFor301: Bool {
		let now = CFAbsoluteTimeGetCurrent()

		if (persistentStore.presentAwayMessageFor301LastEvent + presentAwayMessageFor301Threshold) < now {
			persistentStore.presentAwayMessageFor301LastEvent = now
			return true
		}

		return false
	}

	@objc public var relations: [IRCChannel: ChannelUser] {
		relationsInt.relations
	}

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(nickname:on:)")
	}

	@objc(initWithNickname:onClient:)
	public init(nickname: String, on client: IRCClient) {
		super.init()

		nicknameStorage = nickname
		clientStorage = client
		createNewPersistentStoreObject()
	}

	public required init?(coder _: NSCoder) {
		nil
	}

	deinit {
		cancelRemoveUserTimer()
	}

	private func createNewPersistentStoreObject() {
		persistentStore = UserPersistentStore()
		persistentStore.relations = UserRelations()
	}

	@objc
	public func markAsAway() {
		isAway = true
	}

	@objc
	public func markAsReturned() {
		isAway = false
	}

	override public var description: String {
		"<IRCUser \(nicknameStorage)>"
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

		return clientStorage === other.clientStorage
			&& nicknameStorage == other.nicknameStorage
			&& usernameStorage == other.usernameStorage
			&& addressStorage == other.addressStorage
			&& realNameStorage == other.realNameStorage
			&& accountStorage == other.accountStorage
			&& isAwayStorage == other.isAwayStorage
			&& isIRCopStorage == other.isIRCopStorage
			&& isBotStorage == other.isBotStorage
	}

	@objc(populateDuringCopy:mutableCopy:)
	override public func populateDuringCopy(_ newObject: PortablePropertyObject, mutableCopy _: Bool) {
		guard let object = newObject as? User else {
			return
		}

		object.clientStorage = clientStorage
		object.persistentStore = persistentStore
		object.nicknameStorage = nicknameStorage
		object.usernameStorage = usernameStorage
		object.addressStorage = addressStorage
		object.realNameStorage = realNameStorage
		object.accountStorage = accountStorage
		object.isAwayStorage = isAwayStorage
		object.isIRCopStorage = isIRCopStorage
		object.isBotStorage = isBotStorage
	}

	override public var mutableClass: PortablePropertyObject {
		unsafeBitCast(UserMutable.self, to: PortablePropertyObject.self)
	}

	// MARK: - Remove-user timer

	private func updateRemoveUserTimerBlockToFire() {
		guard let removeUserTimer = persistentStore.removeUserTimer else {
			return
		}

		removeUserTimer.setEventHandler(handler: removeUserTimerBlockToFire())
	}

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

	@objc
	public func cancelRemoveUserTimer() {
		guard let removeUserTimer = persistentStore.removeUserTimer else {
			return
		}

		removeUserTimer.cancel()
		persistentStore.removeUserTimer = nil
	}

	private func removeUserTimerBlockToFire() -> () -> Void {
		weak let client = clientStorage
		weak let user = self

		return {
			guard let strongUser = user else {
				return
			}

			client?.remove(strongUser)
		}
	}

	// MARK: - Relations

	@objc(associateUser:withChannel:)
	public func associate(_ user: ChannelUser, with channel: IRCChannel) {
		relationsInt.associate(user, with: channel)
		toggleRemoveUserTimer()
	}

	@objc(disassociateUserWithChannel:)
	public func disassociateUser(with channel: IRCChannel) {
		relationsInt.disassociateUser(with: channel)
		toggleRemoveUserTimer()
	}

	@objc(userAssociatedWithChannel:)
	public func userAssociated(with channel: IRCChannel) -> ChannelUser? {
		relationsInt.userAssociated(with: channel)
	}

	@objc
	public func relinkRelations() {
		for relatedUser in relationsInt.relatedUsers {
			relatedUser.changeUser(to: self)
		}
	}

	@objc
	public func becamePrimaryUser() {
		updateRemoveUserTimerBlockToFire()
		relinkRelations()
	}

	@objc(enumerateRelations:)
	public func enumerateRelations(
		_ block: (IRCChannel, ChannelUser, UnsafeMutablePointer<ObjCBool>) -> Void
	) {
		relationsInt.enumerateRelations(block)
	}
}

@objc(IRCUserMutable)
public final class UserMutable: User {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyObject {
		unsafeBitCast(User.self, to: PortablePropertyObject.self)
	}

	@objc(initWithClient:)
	public convenience init(client: IRCClient) {
		self.init(nickname: "", on: client)
	}

	@objc override public var nickname: String {
		get { nicknameStorage }
		set { nicknameStorage = newValue }
	}

	@objc override public var username: String? {
		get { usernameStorage }
		set { usernameStorage = newValue }
	}

	@objc override public var address: String? {
		get { addressStorage }
		set { addressStorage = newValue }
	}

	@objc override public var realName: String? {
		get { realNameStorage }
		set { realNameStorage = newValue }
	}

	@objc override public var account: String? {
		get { accountStorage }
		set { accountStorage = newValue }
	}

	@objc override public var isAway: Bool {
		get { isAwayStorage }
		set {
			if isAwayStorage != newValue {
				isAwayStorage = newValue
			}
		}
	}

	@objc override public var isIRCop: Bool {
		get { isIRCopStorage }
		set {
			if isIRCopStorage != newValue {
				isIRCopStorage = newValue
			}
		}
	}

	@objc override public var isBot: Bool {
		get { isBotStorage }
		set {
			if isBotStorage != newValue {
				isBotStorage = newValue
			}
		}
	}
}
