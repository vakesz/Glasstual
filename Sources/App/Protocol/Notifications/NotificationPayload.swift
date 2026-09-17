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
nonisolated struct NotificationPayload: Equatable, Sendable {
	static let clientIdentifierKey = "clientId"
	static let channelIdentifierKey = "channelId"
	static let queryNameKey = "queryName"
	private static let fileTransferIdentifierKey = "fileTransferUniqueIdentifier"
	private static let fileTransferTypeKey = "fileTransferNotificationType"

	var clientIdentifier: String?
	var channelIdentifier: String?
	/// The transfer a file-transfer notification is about, and its event.
	var fileTransferIdentifier: String?
	var fileTransferEventRawValue: Int = 0
	/// The nickname of the private message the notification is about. A reply
	/// typed into the notification after the query was closed opens it again
	/// under this name, because the channel identifier no longer names anything.
	var queryName: String?

	init(
		clientIdentifier: String? = nil,
		channelIdentifier: String? = nil,
		queryName: String? = nil,
		fileTransferIdentifier: String? = nil,
		fileTransferEventRawValue: Int = 0
	) {
		self.clientIdentifier = clientIdentifier
		self.channelIdentifier = channelIdentifier
		self.queryName = queryName
		self.fileTransferIdentifier = fileTransferIdentifier
		self.fileTransferEventRawValue = fileTransferEventRawValue
	}

	/// Reads a payload back out of the dictionary UserNotifications kept.
	init(userInfo: [AnyHashable: Any]) {
		clientIdentifier = userInfo[Self.clientIdentifierKey] as? String
		channelIdentifier = userInfo[Self.channelIdentifierKey] as? String
		queryName = userInfo[Self.queryNameKey] as? String
		fileTransferIdentifier = userInfo[Self.fileTransferIdentifierKey] as? String
		fileTransferEventRawValue = (userInfo[Self.fileTransferTypeKey] as? NSNumber)?.intValue ?? 0
	}

	/// The property list UserNotifications stores with the request.
	var userInfo: [String: PropertyListValue] {
		var result: [String: PropertyListValue] = [:]

		result[Self.clientIdentifierKey] = clientIdentifier.map(PropertyListValue.string)
		result[Self.channelIdentifierKey] = channelIdentifier.map(PropertyListValue.string)
		result[Self.queryNameKey] = queryName.map(PropertyListValue.string)
		result[Self.fileTransferIdentifierKey] = fileTransferIdentifier.map(PropertyListValue.string)

		if fileTransferIdentifier != nil {
			result[Self.fileTransferTypeKey] = .integer(fileTransferEventRawValue)
		}

		return result
	}

	/// The notification group this payload belongs to: one thread per channel,
	/// or per client for a notification the whole connection raised.
	var threadIdentifier: String? {
		guard let clientIdentifier else {
			return nil
		}

		guard let channelIdentifier else {
			return clientIdentifier
		}

		return "\(clientIdentifier)-\(channelIdentifier)"
	}
}
