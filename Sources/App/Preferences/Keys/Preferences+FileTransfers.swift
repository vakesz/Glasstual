// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated extension Preferences {
	/// DCC transfers: how a request is answered and how the listener is reached.
	enum FileTransfers {
		private static let prefix = "File Transfers -> File Transfer "

		static let requestReplyAction = PreferenceKey(
			prefix + "Request Reply Action",
			default: FileTransferRequestBehavior.openDialog
		)

		static let ipAddressDetectionMethod = PreferenceKey(
			prefix + "IP Address Detection Method",
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
			against other: @autoclosure @escaping @Sendable () -> PreferenceKey<UInt16>,
			_ isOrdered: @escaping @Sendable (UInt16, UInt16) -> Bool
		) -> @Sendable (UInt16, [String: PropertyListValue]) -> Bool {
			{ value, values in
				let key = other()
				let limit = values[key.name].flatMap { UInt16.preferenceValue(from: $0.propertyListObject) }
					?? key.defaultValue
				return isOrdered(value, limit)
			}
		}

		static let portRangeStart: PreferenceKey<UInt16> = PreferenceKey(
			prefix + "Port Range Start", default: UInt16(1115),
			validation: { Self.portRange.contains($0) },
			relatedValidation: ordered(against: portRangeEnd, <=)
		)
		static let portRangeEnd: PreferenceKey<UInt16> = PreferenceKey(
			prefix + "Port Range End", default: UInt16(1130),
			validation: { Self.portRange.contains($0) },
			relatedValidation: ordered(against: portRangeStart, >=)
		)
		static let requestsAreReversed = PreferenceKey(prefix + "Requests Use Reverse DCC", default: false)

		static let manuallyEnteredIPAddress = PreferenceKey(
			prefix + "Manually Entered IP Address",
			default: "",
			traits: .unregistered
		)

		static let ipAddressInterfaceName = PreferenceKey(
			prefix + "IP Address Interface Name",
			default: "",
			traits: .unregistered
		)

		/// A security-scoped bookmark, meaningless in another user account.
		static let downloadFolderBookmark = PreferenceKey(
			prefix + "Download Folder Bookmark",
			default: Data(),
			traits: [.unregistered, .excludedFromExport]
		)

		static let preventIdleSystemSleep = PreferenceKey(
			"File Transfers -> Idle System Sleep Prevented During File Transfer",
			default: true
		)

		static let all: [any AnyPreferenceKey] = [
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

extension FileTransferRequestBehavior: PreferenceEnum {}

/// Where the address offered to the other end comes from.
enum FileTransferIPAddressSource: UInt, Sendable {
	// Raw values preserve existing preferences.
	case routerOnly = 3
	case routerAndFirstParty = 1
	case routerAndThirdParty = 4
	case manual = 2
}

extension FileTransferIPAddressSource: PreferenceEnum {}
