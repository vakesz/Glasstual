/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_
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

public typealias IRCAddressBookUserTrackingContainer = AddressBookUserTrackingContainer

public extension Notification.Name {
	static let addressBookTrackingStatusChanged = Self(
		"IRCAddressBookUserTrackingStatusChangedNotification"
	)
	static let addressBookTrackingAddedUser = Self(
		"IRCAddressBookUserTrackingAddedTrackedUserNotification"
	)
	static let addressBookTrackingRemovedUser = Self(
		"IRCAddressBookUserTrackingRemovedTrackedUserNotification"
	)
	static let addressBookTrackingRemovedAllUsers = Self(
		"IRCAddressBookUserTrackingRemovedAllTrackedUsersNotification"
	)
}

public final class AddressBookUserTrackingContainer: NSObject {
	public private(set) weak var client: IRCClient?

	private var availabilityByNickname: [String: Bool] = [:]

	public var trackedUsers: [String: NSNumber] {
		availabilityByNickname.mapValues(NSNumber.init(value:))
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(client:)")
	}

	public init(client: IRCClient) {
		self.client = client
		super.init()
	}

	public func status(ofUser nickname: String) -> IRCAddressBookUserTrackingStatus {
		guard let canonicalNickname = canonicalNickname(matching: nickname) else {
			return .unknown
		}

		return availabilityByNickname[canonicalNickname] == true ? .available : .notAvailable
	}

	public func status(of addressBookEntry: AddressBookEntry) -> IRCAddressBookUserTrackingStatus {
		guard let nickname = addressBookEntry.trackingNickname else {
			return .unknown
		}

		return status(ofUser: nickname)
	}

	public func storedStatus(ofUser nickname: String) -> IRCAddressBookUserTrackingStatus {
		availabilityByNickname[nickname] == true ? .available : .notAvailable
	}

	public func addTrackedUser(_ nickname: String) {
		guard canonicalNickname(matching: nickname) == nil else {
			return
		}

		availabilityByNickname[nickname] = false
		postNotification(named: .addressBookTrackingAddedUser, nickname: nickname)
	}

	public func addTrackedUserWithoutDuplicateCheck(_ nickname: String) {
		availabilityByNickname[nickname] = false
		postNotification(named: .addressBookTrackingAddedUser, nickname: nickname)
	}

	public func removeTrackedUser(_ nickname: String) {
		guard let canonicalNickname = canonicalNickname(matching: nickname) else {
			return
		}

		availabilityByNickname.removeValue(forKey: canonicalNickname)
		postNotification(named: .addressBookTrackingRemovedUser, nickname: canonicalNickname)
	}

	public func removeTrackedUserWithoutLookup(_ nickname: String) {
		availabilityByNickname.removeValue(forKey: nickname)
		postNotification(named: .addressBookTrackingRemovedUser, nickname: nickname)
	}

	public func clearTrackedUsers() {
		availabilityByNickname.removeAll()

		NotificationCenter.default.post(
			name: .addressBookTrackingRemovedAllUsers,
			object: self
		)
	}

	public func status(ofTrackedNickname nickname: String, changedTo newStatus: IRCAddressBookUserTrackingStatus) {
		guard newStatus != .unknown else {
			return
		}

		guard record(newStatus, for: nickname) else {
			return
		}

		NotificationCenter.default.post(
			name: .addressBookTrackingStatusChanged,
			object: self,
			userInfo: ["nickname": nickname, "status": NSNumber(value: newStatus.rawValue)]
		)
	}

	/// Applies the new status and reports whether it is worth telling anyone.
	private func record(
		_ newStatus: IRCAddressBookUserTrackingStatus,
		for nickname: String
	) -> Bool {
		let canonicalNickname = canonicalNickname(matching: nickname)

		switch newStatus {
		case .available, .signedOn:
			availabilityByNickname[canonicalNickname ?? nickname] = true
			return true
		case .notAvailable, .signedOff:
			guard let canonicalNickname else {
				return false
			}

			availabilityByNickname[canonicalNickname] = false
			return true
		case .away, .notAway:
			return canonicalNickname != nil
		case .unknown:
			return false
		@unknown default:
			return false
		}
	}

	private func canonicalNickname(matching nickname: String) -> String? {
		availabilityByNickname.keys.first {
			$0.caseInsensitiveCompare(nickname) == .orderedSame
		}
	}

	private func postNotification(named name: Notification.Name, nickname: String) {
		NotificationCenter.default.post(
			name: name,
			object: self,
			userInfo: ["nickname": nickname]
		)
	}
}
