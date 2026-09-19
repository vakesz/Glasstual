// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated extension SettingsKeys {
	/// DCC transfers: how a request is answered and how the listener is reached.
	enum FileTransfers {
		private static let group = "File Transfers -> "

		static let requestReplyAction = SettingsKey(
			group + "Request Reply Action",
			default: FileTransferRequestBehavior.openDialog
		)

		static let ipAddressDetectionMethod = SettingsKey(
			group + "IP Address Detection Method",
			default: FileTransferIPAddressSource.routerAndFirstParty
		)

		/** The ports the DCC listener may bind.

		 Anything below 1024 is privileged, and a sandboxed process cannot bind
		 one at all, so this is what a valid port is here rather than a
		 suggestion the field makes. */
		static let portRange: ClosedRange<UInt16> = 1024 ... 65535

		/** The ordered-pair rule, written once for both ends of the range.

		 Either end can arrive on its own, so each is checked against whatever
		 the other end holds once the import lands — the value carried in the
		 same file, or the declared default when the file does not carry it. */
		private static func ordered(
			against other: @autoclosure @escaping @Sendable () -> SettingsKey<UInt16>,
			_ isOrdered: @escaping @Sendable (UInt16, UInt16) -> Bool
		) -> @Sendable (UInt16, [String: PropertyListValue]) -> Bool {
			{ value, values in
				let key = other()
				let limit = values[key.name].flatMap { UInt16.settingValue(from: $0.propertyListObject) }
					?? key.defaultValue
				return isOrdered(value, limit)
			}
		}

		static let portRangeStart: SettingsKey<UInt16> = SettingsKey(
			group + "Port Range Start", default: UInt16(1115),
			validation: { Self.portRange.contains($0) },
			relatedValidation: ordered(against: portRangeEnd, <=)
		)
		static let portRangeEnd: SettingsKey<UInt16> = SettingsKey(
			group + "Port Range End", default: UInt16(1130),
			validation: { Self.portRange.contains($0) },
			relatedValidation: ordered(against: portRangeStart, >=)
		)
		static let requestsAreReversed = SettingsKey(group + "Requests Are Reversed", default: false)

		static let manuallyEnteredIPAddress = SettingsKey(
			group + "Manually Entered IP Address",
			default: "",
			traits: .unregistered
		)

		static let ipAddressInterfaceName = SettingsKey(
			group + "IP Address Interface Name",
			default: "",
			traits: .unregistered
		)

		/// A security-scoped bookmark, meaningless in another user account.
		static let downloadFolderBookmark = SettingsKey(
			group + "Download Folder Bookmark",
			default: Data(),
			traits: [.unregistered, .excludedFromExport]
		)

		static let preventIdleSystemSleep = SettingsKey(
			group + "Prevent Idle System Sleep",
			default: true
		)

		static let all: [any AnySettingsKey] = [
			requestReplyAction, ipAddressDetectionMethod, portRangeStart, portRangeEnd,
			requestsAreReversed, manuallyEnteredIPAddress, ipAddressInterfaceName,
			downloadFolderBookmark, preventIdleSystemSleep,
		]
	}
}

/** What happens when someone offers a file.

 Stored as the integer it declares; a stored value with no matching case falls
 back to the key's declared default. */
enum FileTransferRequestBehavior: UInt, Sendable {
	case ignore = 1
	case openDialog
	case automaticallyDownload
}

extension FileTransferRequestBehavior: SettingEnum {}

/// Where the address offered to the other end comes from.
enum FileTransferIPAddressSource: UInt, Sendable {
	// The raw value is what is stored, so a case is added at the end: inserting
	// one in the middle changes what every later case already means.
	case routerOnly
	case routerAndFirstParty
	case routerAndThirdParty
	case manual
}

extension FileTransferIPAddressSource: SettingEnum {}
