/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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

public nonisolated extension Preferences { // nonisolated: value
	/// DCC transfers: how a request is answered and how the listener is reached.
	enum FileTransfers {
		private static let prefix = "File Transfers -> File Transfer "

		public static let requestReplyAction = PreferenceKey(
			prefix + "Request Reply Action",
			default: FileTransferRequestBehavior.openDialog
		)

		public static let ipAddressDetectionMethod = PreferenceKey(
			prefix + "IP Address Detection Method",
			default: FileTransferIPAddressSource.routerAndFirstParty
		)

		/** The ports the DCC listener may bind.

		 Anything below 1024 is privileged, and a sandboxed process cannot bind
		 one at all, so this is what a valid port is here rather than a
		 suggestion the field makes. */
		public static let portRange: ClosedRange<UInt16> = 1024 ... 65535

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

		public static let portRangeStart: PreferenceKey<UInt16> = PreferenceKey(
			prefix + "Port Range Start", default: UInt16(1115),
			validation: { Self.portRange.contains($0) },
			relatedValidation: ordered(against: portRangeEnd, <=)
		)
		public static let portRangeEnd: PreferenceKey<UInt16> = PreferenceKey(
			prefix + "Port Range End", default: UInt16(1130),
			validation: { Self.portRange.contains($0) },
			relatedValidation: ordered(against: portRangeStart, >=)
		)
		public static let requestsAreReversed = PreferenceKey(prefix + "Requests Use Reverse DCC", default: false)

		public static let manuallyEnteredIPAddress = PreferenceKey(
			prefix + "Manually Entered IP Address",
			default: "",
			traits: .unregistered
		)

		public static let ipAddressInterfaceName = PreferenceKey(
			prefix + "IP Address Interface Name",
			default: "",
			traits: .unregistered
		)

		/// A security-scoped bookmark, meaningless in another user account.
		public static let downloadFolderBookmark = PreferenceKey(
			prefix + "Download Folder Bookmark",
			default: Data(),
			traits: [.unregistered, .excludedFromExport]
		)

		public static let preventIdleSystemSleep = PreferenceKey(
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

public nonisolated extension Preferences { // nonisolated: value
	/// Settings owned by the bundled extensions, declared here so they are
	/// catalogued and travel with an exported configuration.
	enum Extensions {
		public static let chatFilters = UntypedPreferenceKey(
			FirstPartyPluginPreferences.chatFilters, validation: PreferencesPayloadValidation.chatFilters
		)

		public static let caffeinePreventSleep = PreferenceKey(
			FirstPartyPluginPreferences.caffeinePreventSleep.name,
			default: FirstPartyPluginPreferences.caffeinePreventSleep.defaultValue,
			traits: .unregistered
		)

		public static let smileyServiceEnabled = PreferenceKey(
			FirstPartyPluginPreferences.smileyServiceEnabled.name,
			default: FirstPartyPluginPreferences.smileyServiceEnabled.defaultValue,
			traits: .unregistered
		)

		public static let smileyExtraEmoticons = PreferenceKey(
			FirstPartyPluginPreferences.smileyExtraEmoticons.name,
			default: FirstPartyPluginPreferences.smileyExtraEmoticons.defaultValue,
			traits: .unregistered
		)

		public static let wikiLinkServiceEnabled = PreferenceKey(
			"Wiki-style Link Parser Extension -> Service Enabled",
			default: false,
			traits: .unregistered
		)

		public static let wikiLinkPrefixes = UntypedPreferenceKey(
			"Wiki-style Link Parser Extension -> Link Prefixes", validation: { $0.dictionary != nil }
		)

		/// The seven "Feature Disabled" switches of the system profiler.
		public static let systemProfilerFeatures = FirstPartyPluginPreferences.systemProfilerFeatures.map {
			PreferenceKey(
				$0.name,
				default: $0.defaultValue,
				traits: .unregistered
			)
		}

		static let all: [any AnyPreferenceKey] = [
			chatFilters, caffeinePreventSleep, smileyServiceEnabled, smileyExtraEmoticons,
			wikiLinkServiceEnabled, wikiLinkPrefixes,
		] + systemProfilerFeatures
	}
}
