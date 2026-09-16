/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
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
 *
 *********************************************************************** */

import Foundation

enum NetsplitSummaryPolicy {
	static let nicknameLimit: UInt = 10

	static func servers(from parameters: [String]?) -> (String, String) {
		(parameters?.first ?? "?", parameters?.dropFirst().first ?? "?")
	}

	static func accepts(command: String) -> Bool {
		command.caseInsensitiveCompare("QUIT") == .orderedSame ||
			command.caseInsensitiveCompare("JOIN") == .orderedSame
	}
}

/// The nicknames a netsplit summary names, cut to `limit` with a count of how
/// many it left out: a split can carry hundreds of names, and a console line
/// that lists them all is unreadable.
func netsplitNicknameList(_ nicknames: [String], limit: UInt) -> String {
	guard UInt(nicknames.count) > limit else {
		return nicknames.joined(separator: ", ")
	}

	let shown = nicknames.prefix(Int(limit)).joined(separator: ", ")

	return String(localized: .IRC.netsplitAndNetjoinSummariesMore(shown, arg2: UInt(nicknames.count - Int(limit))))
}

extension Client {
	func replayNetsplitBatch(_ batchMessage: MessageBatch) {
		collapsedNetsplitBatch = batchMessage
		collapsedNetsplitNicknames = [:]
		processQueuedMessages(of: batchMessage)

		let recordedNicknames = collapsedNetsplitNicknames
		collapsedNetsplitBatch = nil
		collapsedNetsplitNicknames = nil

		let isNetsplit = batchMessage.batchType == "netsplit"
		let (firstServer, secondServer) = NetsplitSummaryPolicy.servers(from: batchMessage.batchParameters)
		for channel in channelList {
			guard let nicknames = recordedNicknames?[channel.uniqueIdentifier],
			      nicknames.isEmpty == false,
			      environment.preferences.showJoinLeave,
			      !channel.config.ignoreGeneralEventMessages
			else { continue }

			let nicknameList = netsplitNicknameList(
				nicknames,
				limit: NetsplitSummaryPolicy.nicknameLimit
			)
			let message = if isNetsplit {
				String(localized: .IRC.netsplitBetweenAndUsersLeft(firstServer, secondServer, arg3: UInt(nicknames.count), nicknameList))
			} else {
				String(localized: .IRC.netjoinBetweenAndUsersRejoined(firstServer, secondServer, arg3: UInt(nicknames.count), nicknameList))
			}
			print(
				message,
				by: nil,
				in: channel,
				as: isNetsplit ? .quit : .join,
				command: isNetsplit ? "QUIT" : "JOIN"
			)
		}
	}

	func collapseNetsplitMessage(_ message: Message, in channel: Channel) -> Bool {
		guard let collapsedBatch = collapsedNetsplitBatch as? MessageBatch,
		      NetsplitSummaryPolicy.accepts(command: message.command),
		      batchMessage(ofType: collapsedBatch.batchType ?? "", containing: message) != nil,
		      let nickname = message.senderNickname,
		      !nickname.isEmpty
		else { return false }

		let identifier = channel.uniqueIdentifier
		var nicknames = collapsedNetsplitNicknames?[identifier] ?? []
		if nicknames.contains(nickname) == false {
			nicknames.append(nickname)
		}
		collapsedNetsplitNicknames?[identifier] = nicknames
		return true
	}
}
