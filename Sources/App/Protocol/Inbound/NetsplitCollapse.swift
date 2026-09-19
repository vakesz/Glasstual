// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The netsplit or netjoin batch being collapsed into one summary line, and the
 nicknames it has named so far, per conversation identifier, in arrival order.

 A batch is only ever collapsed inside ``ServerSession/replayNetsplitBatch(_:)``, so
 "which batch" and "what it gathered" begin and end together rather than as two
 optionals that have to agree. */
struct NetsplitCollapse {
	private(set) var batch: MessageBatch?
	private var nicknamesByConversation: [String: [String]] = [:]

	var isCollapsing: Bool {
		batch != nil
	}

	mutating func begin(_ batch: MessageBatch) {
		self.batch = batch
		nicknamesByConversation = [:]
	}

	/// Ends the collapse and hands back the nicknames it gathered.
	mutating func finish() -> [String: [String]] {
		defer { self = NetsplitCollapse() }

		return nicknamesByConversation
	}

	/// Notes that `nickname` was named in the conversation `conversationIdentifier`
	/// identifies, unless the batch has already named them there.
	mutating func record(_ nickname: String, in conversationIdentifier: String) {
		var nicknames = nicknamesByConversation[conversationIdentifier] ?? []
		guard nicknames.contains(nickname) == false else { return }

		nicknames.append(nickname)
		nicknamesByConversation[conversationIdentifier] = nicknames
	}
}

enum NetsplitSummaryPolicy {
	static let nicknameLimit: UInt = 10

	static func servers(from parameters: [String]?) -> (String, String) {
		(parameters?.first ?? "?", parameters?.dropFirst().first ?? "?")
	}

	static func accepts(command: RemoteCommand?) -> Bool {
		command == .quit || command == .join
	}

	/// The nicknames a netsplit summary names, cut to `limit` with a count of how
	/// many it left out: a split can carry hundreds of names, and a console line
	/// that lists them all is unreadable.
	static func nicknameList(_ nicknames: [String], limit: UInt) -> String {
		guard UInt(nicknames.count) > limit else {
			return nicknames.joined(separator: ", ")
		}

		let shown = nicknames.prefix(Int(limit)).joined(separator: ", ")

		return String(localized: .IRC.netsplitAndNetjoinSummariesMore(shown, arg2: UInt(nicknames.count - Int(limit))))
	}
}

extension ServerSession {
	func replayNetsplitBatch(_ batchMessage: MessageBatch) {
		netsplitCollapse.begin(batchMessage)
		processQueuedMessages(of: batchMessage)

		let recordedNicknames = netsplitCollapse.finish()

		let isNetsplit = batchMessage.batchType == "netsplit"
		let (firstServer, secondServer) = NetsplitSummaryPolicy.servers(from: batchMessage.batchParameters)
		for conversation in conversationList {
			guard let nicknames = recordedNicknames[conversation.uniqueIdentifier],
			      nicknames.isEmpty == false,
			      environment.settings.showJoinLeave,
			      !conversation.config.ignoreGeneralEventMessages
			else { continue }

			let nicknameList = NetsplitSummaryPolicy.nicknameList(
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
				in: conversation,
				as: isNetsplit ? .quit : .join,
				command: isNetsplit ? "QUIT" : "JOIN"
			)
		}
	}

	func collapseNetsplitMessage(_ message: Message, in conversation: Conversation) -> Bool {
		guard let collapsedBatch = netsplitCollapse.batch,
		      NetsplitSummaryPolicy.accepts(command: message.remoteCommand),
		      batchMessage(ofType: collapsedBatch.batchType ?? "", containing: message) != nil,
		      let nickname = message.senderNickname,
		      !nickname.isEmpty
		else { return false }

		netsplitCollapse.record(nickname, in: conversation.uniqueIdentifier)

		return true
	}
}
