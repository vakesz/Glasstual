// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension Notification.Name {
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

/// The nickname a tracking notification is about.
nonisolated let addressBookTrackingNicknameKey = "nickname"

/// The `AddressBookUserTrackingStatus` raw value a status-change
/// notification carries.
nonisolated let addressBookTrackingStatusKey = "status"

final class AddressBookUserTrackingContainer {
	/** How the server folds nicknames.

	 The tracker holds the spelling each nickname was added under and folds on
	 lookup, so a `005` that changes `CASEMAPPING` changes only this. The client
	 sets it where it rekeys the user list, which is the same moment. */
	var caseMapping = ISupportCaseMapping.rfc1459

	private var availabilityByNickname: [String: Bool] = [:]

	/// Every tracked nickname, as added, against whether that person is known
	/// to be online.
	var trackedUsers: [String: Bool] {
		availabilityByNickname
	}

	func status(ofUser nickname: String) -> AddressBookUserTrackingStatus {
		guard let canonicalNickname = canonicalNickname(matching: nickname) else {
			return .unknown
		}

		return availabilityByNickname[canonicalNickname] == true ? .available : .notAvailable
	}

	func status(of addressBookEntry: AddressBookEntry) -> AddressBookUserTrackingStatus {
		guard let nickname = addressBookEntry.trackingNickname else {
			return .unknown
		}

		return status(ofUser: nickname)
	}

	func addTrackedUser(_ nickname: String) {
		guard canonicalNickname(matching: nickname) == nil else {
			return
		}

		availabilityByNickname[nickname] = false
		postNotification(named: .addressBookTrackingAddedUser, nickname: nickname)
	}

	func addTrackedUserWithoutDuplicateCheck(_ nickname: String) {
		availabilityByNickname[nickname] = false
		postNotification(named: .addressBookTrackingAddedUser, nickname: nickname)
	}

	func removeTrackedUser(_ nickname: String) {
		guard let canonicalNickname = canonicalNickname(matching: nickname) else {
			return
		}

		availabilityByNickname.removeValue(forKey: canonicalNickname)
		postNotification(named: .addressBookTrackingRemovedUser, nickname: canonicalNickname)
	}

	func removeTrackedUserWithoutLookup(_ nickname: String) {
		availabilityByNickname.removeValue(forKey: nickname)
		postNotification(named: .addressBookTrackingRemovedUser, nickname: nickname)
	}

	func clearTrackedUsers() {
		availabilityByNickname.removeAll()

		NotificationCenter.default.post(
			name: .addressBookTrackingRemovedAllUsers,
			object: self
		)
	}

	func status(ofTrackedNickname nickname: String, changedTo newStatus: AddressBookUserTrackingStatus) {
		guard newStatus != .unknown else {
			return
		}

		guard record(newStatus, for: nickname) else {
			return
		}

		NotificationCenter.default.post(
			name: .addressBookTrackingStatusChanged,
			object: self,
			userInfo: [
				addressBookTrackingNicknameKey: nickname,
				addressBookTrackingStatusKey: newStatus.rawValue,
			]
		)
	}

	/// Applies the new status and reports whether it is worth telling anyone.
	private func record(
		_ newStatus: AddressBookUserTrackingStatus,
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

	/** The stored spelling of `nickname`, or `nil` when nobody by that name is
	 tracked.

	 Folded the way the server folds nicknames rather than by
	 `caseInsensitiveCompare`, which is Unicode folding: under RFC 1459 casing
	 `nick[home]` and `nick{home}` are one person, and the tracker used to hold
	 two entries for them and report each other's presence changes. */
	private func canonicalNickname(matching nickname: String) -> String? {
		let folded = casefolded(nickname)

		return availabilityByNickname.keys.first { casefolded($0) == folded }
	}

	private func casefolded(_ nickname: String) -> String {
		ISupportTokenParser.casefold(nickname, caseMapping: caseMapping)
	}

	private func postNotification(named name: Notification.Name, nickname: String) {
		NotificationCenter.default.post(
			name: name,
			object: self,
			userInfo: [addressBookTrackingNicknameKey: nickname]
		)
	}
}
