// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
