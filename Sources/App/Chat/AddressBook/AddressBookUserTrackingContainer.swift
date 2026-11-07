// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What a tracking message carries besides its subject, as `userInfo`.
private enum AddressBookTrackingKey {
	static let nickname = "nickname"
	static let status = "status"
}

/// A nickname whose tracked status changed. The status raw values are a wire
/// vocabulary, see ``AddressBookUserTrackingStatus``.
struct AddressBookTrackingStatusChanged: NotificationCenter.MainActorMessage {
	typealias Subject = AddressBookUserTrackingContainer

	nonisolated static let name = Notification.Name("Glasstual.addressBookTrackingStatusChanged")

	let subject: AddressBookUserTrackingContainer
	let nickname: String
	let status: AddressBookUserTrackingStatus

	static func makeMessage(_ notification: Notification) -> Self? {
		guard let subject = notification.object as? AddressBookUserTrackingContainer,
		      let nickname = notification.userInfo?[AddressBookTrackingKey.nickname] as? String,
		      let rawStatus = notification.userInfo?[AddressBookTrackingKey.status] as? UInt,
		      let status = AddressBookUserTrackingStatus(rawValue: rawStatus)
		else { return nil }
		return Self(subject: subject, nickname: nickname, status: status)
	}

	static func makeNotification(_ message: Self) -> Notification {
		Notification(
			name: name,
			object: message.subject,
			userInfo: [
				AddressBookTrackingKey.nickname: message.nickname,
				AddressBookTrackingKey.status: message.status.rawValue,
			]
		)
	}
}

/// A nickname was added to the tracked list.
struct AddressBookTrackedUserAdded: NotificationCenter.MainActorMessage {
	typealias Subject = AddressBookUserTrackingContainer

	nonisolated static let name = Notification.Name("Glasstual.addressBookTrackingAddedUser")

	let subject: AddressBookUserTrackingContainer
	let nickname: String

	static func makeMessage(_ notification: Notification) -> Self? {
		guard let subject = notification.object as? AddressBookUserTrackingContainer,
		      let nickname = notification.userInfo?[AddressBookTrackingKey.nickname] as? String
		else { return nil }
		return Self(subject: subject, nickname: nickname)
	}

	static func makeNotification(_ message: Self) -> Notification {
		Notification(
			name: name,
			object: message.subject,
			userInfo: [AddressBookTrackingKey.nickname: message.nickname]
		)
	}
}

/// A nickname was removed from the tracked list.
struct AddressBookTrackedUserRemoved: NotificationCenter.MainActorMessage {
	typealias Subject = AddressBookUserTrackingContainer

	nonisolated static let name = Notification.Name("Glasstual.addressBookTrackingRemovedUser")

	let subject: AddressBookUserTrackingContainer
	let nickname: String

	static func makeMessage(_ notification: Notification) -> Self? {
		guard let subject = notification.object as? AddressBookUserTrackingContainer,
		      let nickname = notification.userInfo?[AddressBookTrackingKey.nickname] as? String
		else { return nil }
		return Self(subject: subject, nickname: nickname)
	}

	static func makeNotification(_ message: Self) -> Notification {
		Notification(
			name: name,
			object: message.subject,
			userInfo: [AddressBookTrackingKey.nickname: message.nickname]
		)
	}
}

/// The tracked list was emptied.
struct AddressBookTrackedUsersCleared: SubjectMessage {
	typealias Subject = AddressBookUserTrackingContainer

	nonisolated static let name = Notification.Name("Glasstual.addressBookTrackingRemovedAllUsers")

	let subject: AddressBookUserTrackingContainer
}

final class AddressBookUserTrackingContainer {
	/** How the server folds nicknames.

	 The tracker holds the spelling each nickname was added under and folds on
	 lookup, so a `005` that changes `CASEMAPPING` changes only this. The session
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
		NotificationCenter.default.post(AddressBookTrackedUserAdded(subject: self, nickname: nickname), subject: self)
	}

	func addTrackedUserWithoutDuplicateCheck(_ nickname: String) {
		availabilityByNickname[nickname] = false
		NotificationCenter.default.post(AddressBookTrackedUserAdded(subject: self, nickname: nickname), subject: self)
	}

	func removeTrackedUser(_ nickname: String) {
		guard let canonicalNickname = canonicalNickname(matching: nickname) else {
			return
		}

		availabilityByNickname.removeValue(forKey: canonicalNickname)
		NotificationCenter.default.post(AddressBookTrackedUserRemoved(subject: self, nickname: canonicalNickname), subject: self)
	}

	func removeTrackedUserWithoutLookup(_ nickname: String) {
		availabilityByNickname.removeValue(forKey: nickname)
		NotificationCenter.default.post(AddressBookTrackedUserRemoved(subject: self, nickname: nickname), subject: self)
	}

	func clearTrackedUsers() {
		availabilityByNickname.removeAll()

		AddressBookTrackedUsersCleared(subject: self).post()
	}

	func status(ofTrackedNickname nickname: String, changedTo newStatus: AddressBookUserTrackingStatus) {
		guard newStatus != .unknown, record(newStatus, for: nickname) else {
			return
		}

		NotificationCenter.default.post(
			AddressBookTrackingStatusChanged(subject: self, nickname: nickname, status: newStatus),
			subject: self
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
		IRCCaseFolding.fold(nickname, using: caseMapping)
	}
}
