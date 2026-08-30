/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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
 *********************************************************************** */

import CocoaExtensions
import Foundation

@MainActor
extension IRCClient {
	func dispatchIgnoreCommand(_ parsed: ParsedUserCommand, targetChannel: IRCChannel?) -> Bool {
		let command = parsed.localCommand
		guard command == .ignore || command == .unignore else { return false }
		let isIgnore = command == .ignore
		var arguments = parsed.arguments
		let nickname = arguments.next()
		guard nickname.isEmpty == false, targetChannel != nil, let member = findUser(nickname) else {
			showIgnoreConfiguration(isIgnore: isIgnore, context: isIgnore ? nickname : nil)
			return true
		}
		let hostmask = member.hostmask ?? "\(nickname)!*@*"
		let matches = config.ignoreList.filter { $0.entryType == .ignore && $0.checkMatch(hostmask) }
		if isIgnore, matches.isEmpty == false {
			printDebugInformation(IRCCommandStrings.Ignore.alreadyExists(nickname: member.nickname))
			return true
		}
		if isIgnore == false, matches.isEmpty {
			printDebugInformation(IRCCommandStrings.Ignore.notFound(nickname: member.nickname))
			return true
		}
		if isIgnore == false, matches.count > 1 {
			printDebugInformation(IRCCommandStrings.Ignore.ambiguous(nickname: member.nickname))
			return true
		}
		var mutableConfig = config
		if isIgnore {
			let ignore = AddressBookEntry.newIgnoreEntry(forHostmask: banMask(for: member))
			printDebugInformation(
				IRCCommandStrings.Ignore.added(nickname: member.nickname, hostmask: ignore.hostmask)
			)
			mutableConfig.ignoreList.append(ignore)
		} else if let ignore = matches.first {
			printDebugInformation(
				IRCCommandStrings.Ignore.removed(nickname: member.nickname, hostmask: ignore.hostmask)
			)
			mutableConfig.ignoreList.removeAll { $0.uniqueIdentifier == ignore.uniqueIdentifier }
		}
		updateConfig(mutableConfig)
		clearAddressBookCache(forHostmask: hostmask)
		return true
	}

	private func showIgnoreConfiguration(isIgnore: Bool, context: String?) {
		let selection = isIgnore ? MenuDialogSelection.serverNewIgnoreEntry : MenuDialogSelection.serverAddressBook
		menu?.showServerPropertiesSheet(
			for: self,
			selection: selection,
			context: isIgnore ? (context ?? "") : nil
		)
	}
}
