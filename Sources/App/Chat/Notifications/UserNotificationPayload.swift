// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** What a delivered notification carries back when the person clicks it.

 `UNNotificationContent.userInfo` is a property-list dictionary, so the keys
 below are the only place the strings appear; every producer and reader inside
 the application works with the value. It used to be an untyped dictionary
 passed whole from the protocol layer to the delegate callback, with each
 reader guessing at the keys. */
nonisolated struct UserNotificationPayload: Equatable, Sendable {
	static let sessionIdentifierKey = "clientId"
	static let conversationIdentifierKey = "channelId"
	static let directNicknameKey = "queryName"
	private static let fileTransferIdentifierKey = "fileTransferUniqueIdentifier"
	private static let fileTransferTypeKey = "fileTransferNotificationType"

	var sessionIdentifier: String?
	var conversationIdentifier: String?
	/// The transfer a file-transfer notification is about, and its event.
	var fileTransferIdentifier: String?
	var fileTransferEventRawValue: Int = 0
	/// The nickname of the one-to-one conversation the notification is about. A
	/// reply typed into the notification after that conversation was closed opens
	/// it again under this name, because the conversation identifier no longer
	/// names anything.
	var directNickname: String?

	init(
		sessionIdentifier: String? = nil,
		conversationIdentifier: String? = nil,
		directNickname: String? = nil,
		fileTransferIdentifier: String? = nil,
		fileTransferEventRawValue: Int = 0
	) {
		self.sessionIdentifier = sessionIdentifier
		self.conversationIdentifier = conversationIdentifier
		self.directNickname = directNickname
		self.fileTransferIdentifier = fileTransferIdentifier
		self.fileTransferEventRawValue = fileTransferEventRawValue
	}

	/// Reads a payload back out of the dictionary UserNotifications kept.
	init(userInfo: [AnyHashable: Any]) {
		sessionIdentifier = userInfo[Self.sessionIdentifierKey] as? String
		conversationIdentifier = userInfo[Self.conversationIdentifierKey] as? String
		directNickname = userInfo[Self.directNicknameKey] as? String
		fileTransferIdentifier = userInfo[Self.fileTransferIdentifierKey] as? String
		fileTransferEventRawValue = (userInfo[Self.fileTransferTypeKey] as? NSNumber)?.intValue ?? 0
	}

	/// The property list UserNotifications stores with the request.
	var userInfo: [String: PropertyListValue] {
		var result: [String: PropertyListValue] = [:]

		result[Self.sessionIdentifierKey] = sessionIdentifier.map(PropertyListValue.string)
		result[Self.conversationIdentifierKey] = conversationIdentifier.map(PropertyListValue.string)
		result[Self.directNicknameKey] = directNickname.map(PropertyListValue.string)
		result[Self.fileTransferIdentifierKey] = fileTransferIdentifier.map(PropertyListValue.string)

		if fileTransferIdentifier != nil {
			result[Self.fileTransferTypeKey] = .integer(fileTransferEventRawValue)
		}

		return result
	}

	func isInScope(of sessionIdentifier: String, conversationIdentifier: String?) -> Bool {
		self.sessionIdentifier == sessionIdentifier && self.conversationIdentifier == conversationIdentifier
	}

	/// The notification group this payload belongs to: one thread per
	/// conversation, or per session for a notification the whole connection raised.
	var threadIdentifier: String? {
		guard let sessionIdentifier else {
			return nil
		}

		guard let conversationIdentifier else {
			return sessionIdentifier
		}

		return "\(sessionIdentifier)-\(conversationIdentifier)"
	}
}
