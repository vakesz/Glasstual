// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What an ignore entry ignores, as `/ignore` names it.
nonisolated enum IgnoreFlag: String, CaseIterable, Sendable {
	case publicMessages = "public"
	case privateMessages = "private"
	case notices
	case ctcp
	case dcc
	case events
	case media
	case highlights
	case mute

	/// Whether `entry` ignores this.
	func isSet(in entry: AddressBookEntry) -> Bool {
		switch self {
		case .publicMessages: entry.ignorePublicMessages
		case .privateMessages: entry.ignorePrivateMessages
		case .notices: entry.ignoreNoticeMessages
		case .ctcp: entry.ignoreClientToClientProtocol
		case .dcc: entry.ignoreFileTransferRequests
		case .events: entry.ignoreGeneralEventMessages
		case .media: entry.ignoreInlineMedia
		case .highlights: entry.ignorePublicMessageHighlights && entry.ignorePrivateMessageHighlights
		case .mute: entry.muteMessages
		}
	}

	func set(_ enabled: Bool, on entry: inout AddressBookEntry) {
		switch self {
		case .publicMessages: entry.ignorePublicMessages = enabled
		case .privateMessages: entry.ignorePrivateMessages = enabled
		case .notices: entry.ignoreNoticeMessages = enabled
		case .ctcp: entry.ignoreClientToClientProtocol = enabled
		case .dcc: entry.ignoreFileTransferRequests = enabled
		case .events: entry.ignoreGeneralEventMessages = enabled
		case .media: entry.ignoreInlineMedia = enabled
		case .highlights:
			entry.ignorePublicMessageHighlights = enabled
			entry.ignorePrivateMessageHighlights = enabled
		case .mute: entry.muteMessages = enabled
		}
	}
}

/** The forms of `/ignore` and `/unignore` that edit the address book
 directly, the way its editor does: by mask, by number and with flags.

 A bare nickname with no flags keeps its older meaning — the member's own
 mask, looked up in the conversation — and is left to the caller. */
nonisolated enum IgnoreCommandRequest: Equatable, Sendable {
	case list
	/// Adds or changes the entry for `mask`, turning flags on and off on top
	/// of what a new ignore ignores.
	case ignore(mask: String, flags: [IgnoreFlag: Bool])
	case unignoreMask(String)
	case unignoreNumber(Int)
	case unknownFlag(String)

	init?(command: LocalCommand, arguments: String) {
		let words = arguments.split(whereSeparator: \.isWhitespace).map(String.init)
		guard let first = words.first else { return nil }
		let isMask = first.contains("!") || first.contains("@") || first.contains("*")
		switch command {
		case .ignore:
			if first.lowercased() == "list", words.count == 1 {
				self = .list
				return
			}
			var flags: [IgnoreFlag: Bool] = [:]
			for word in words.dropFirst() {
				guard let sign = word.first, sign == "+" || sign == "-",
				      let flag = IgnoreFlag(rawValue: String(word.dropFirst()).lowercased())
				else {
					self = .unknownFlag(word)
					return
				}
				flags[flag] = sign == "+"
			}
			guard isMask || flags.isEmpty == false else { return nil }
			self = .ignore(mask: isMask ? first : "\(first)!*@*", flags: flags)
		case .unignore:
			guard words.count == 1 else { return nil }
			if let number = Int(first), number > 0 {
				self = .unignoreNumber(number)
			} else if isMask {
				self = .unignoreMask(first)
			} else {
				return nil
			}
		default:
			return nil
		}
	}
}

extension ServerSession {
	/// Carries out an `/ignore` or `/unignore` that names a mask, a number,
	/// flags or `list`.
	func performIgnoreCommand(_ request: IgnoreCommandRequest) {
		let ignores = config.ignoreList.filter { $0.entryType == .ignore }
		var mutableConfig = config
		switch request {
		case .list:
			guard ignores.isEmpty == false else {
				printDebugInformation(String(localized: .IRC.ignoreListEmpty(name)))
				return
			}
			printDebugInformation(String(localized: .IRC.ignoreListHeader(name)))
			for (index, entry) in ignores.enumerated() {
				let flags = IgnoreFlag.allCases.filter { $0.isSet(in: entry) }.map(\.rawValue).joined(separator: " ")
				printDebugInformation(String(localized: .IRC.ignoreListEntry(index + 1, entry.hostmask, flags)))
			}
			return
		case let .unknownFlag(word):
			let known = IgnoreFlag.allCases.map { "+\($0.rawValue)" }.joined(separator: " ")
			printDebugInformation(String(localized: .IRC.ignoreUnknownFlag(word, known)))
			return
		case let .ignore(mask, flags):
			var entry = mutableConfig.ignoreList.first {
				$0.entryType == .ignore && $0.hostmask.caseInsensitiveCompare(mask) == .orderedSame
			} ?? AddressBookEntry.newIgnoreEntry(forHostmask: mask)
			for (flag, enabled) in flags {
				flag.set(enabled, on: &entry)
			}
			if let index = mutableConfig.ignoreList.firstIndex(where: { $0.uniqueIdentifier == entry.uniqueIdentifier }) {
				mutableConfig.ignoreList[index] = entry
			} else {
				mutableConfig.ignoreList.append(entry)
			}
			printDebugInformation(String(localized: .IRC.ignoreSaved(entry.hostmask)))
		case let .unignoreMask(mask):
			guard let entry = ignores.first(where: { $0.hostmask.caseInsensitiveCompare(mask) == .orderedSame }) else {
				printDebugInformation(String(localized: .IRC.ignoreNotFound(mask)))
				return
			}
			mutableConfig.ignoreList.removeAll { $0.uniqueIdentifier == entry.uniqueIdentifier }
			printDebugInformation(String(localized: .IRC.ignoreRemoved(entry.hostmask)))
		case let .unignoreNumber(number):
			guard ignores.indices.contains(number - 1) else {
				printDebugInformation(String(localized: .IRC.ignoreNotFound(String(number))))
				return
			}
			let entry = ignores[number - 1]
			mutableConfig.ignoreList.removeAll { $0.uniqueIdentifier == entry.uniqueIdentifier }
			printDebugInformation(String(localized: .IRC.ignoreRemoved(entry.hostmask)))
		}
		updateConfig(mutableConfig)
		clearAddressBookCache()
		chatSession?.save()
	}
}
