// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

@MainActor
extension Client {
	func dispatchIgnoreCommand(_ parsed: ParsedUserCommand, targetChannel: Channel?) {
		let isIgnore = parsed.localCommand == .ignore
		var arguments = parsed.arguments
		let nickname = arguments.next()
		guard nickname.isEmpty == false, targetChannel != nil, let member = findUser(nickname) else {
			menu?.showServerPropertiesSheet(
				for: self,
				selection: isIgnore ? .newIgnoreEntry(hostmask: nickname) : .addressBook
			)
			return
		}
		let hostmask = member.hostmask ?? "\(nickname)!*@*"
		let matches = config.ignoreList.filter { $0.entryType == .ignore && $0.checkMatch(hostmask) }
		if isIgnore, matches.isEmpty == false {
			printDebugInformation(String(localized: .IRC.ignoreAlreadyExistsThatMatches(member.nickname)))
			return
		}
		if isIgnore == false, matches.isEmpty {
			printDebugInformation(String(localized: .IRC.noIgnoresCouldBeFound(member.nickname)))
			return
		}
		if isIgnore == false, matches.count > 1 {
			printDebugInformation(String(localized: .IRC.cannotRemoveIgnoreForBecauseGlasstual(member.nickname)))
			return
		}
		var mutableConfig = config
		if isIgnore {
			let ignore = AddressBookEntry.newIgnoreEntry(forHostmask: banMask(for: member))
			printDebugInformation(
				String(localized: .IRC.addedIgnoreThatMatchesWithPattern(member.nickname, ignore.hostmask))
			)
			mutableConfig.ignoreList.append(ignore)
		} else if let ignore = matches.first {
			printDebugInformation(
				String(localized: .IRC.removedIgnoreThatMatchesWithPattern(member.nickname, ignore.hostmask))
			)
			mutableConfig.ignoreList.removeAll { $0.uniqueIdentifier == ignore.uniqueIdentifier }
		}
		updateConfig(mutableConfig)
		clearAddressBookCache(forHostmask: hostmask)
	}
}
