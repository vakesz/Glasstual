// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerSession {
	@MainActor
	@discardableResult
	func sendReaction(
		_ emoji: String,
		toMessageIdentifier messageIdentifier: String,
		in conversation: Conversation
	) -> Bool {
		guard emoji.isEmpty == false, messageIdentifier.isEmpty == false,
		      isLoggedIn, isTerminating == false, isQuitting == false, isDisconnecting == false,
		      conversation.isConsole == false, conversation.isActive,
		      conversation.associatedSession === self,
		      conversationList.contains(where: { $0 === conversation })
		else {
			return false
		}

		let tags = ["+draft/react": emoji, "+draft/reply": messageIdentifier]
		guard sendTagMessage(tags, toTarget: conversation.name) else { return false }

		deliverTags(
			["draft/react": emoji, "draft/reply": messageIdentifier],
			fromSender: userNickname,
			in: conversation
		)
		return true
	}

	func sendPrivmsg(_ message: String, to conversation: Conversation) {
		sendText(NSAttributedString(string: message), as: .privmsg, to: conversation)
	}

	/// The `String` spelling is for the verb a person typed after `/ctcp`, which
	/// this session is free to know nothing about. Everything it sends on its own
	/// goes out through the ``CTCPVerb`` overload.
	func sendCTCPQuery(_ nickname: String, command: String, text: String?) {
		send(
			.privmsg,
			arguments: [nickname, CTCPPayload.framed(command: command, text: text, sanitizingLineBreaks: false)]
		)
	}

	func sendCTCPQuery(_ nickname: String, command: CTCPVerb, text: String?) {
		sendCTCPQuery(nickname, command: command.wireName, text: text)
	}

	func sendCTCPReply(_ nickname: String, command: String, text: String?) {
		send(
			.notice,
			arguments: [nickname, CTCPPayload.framed(command: command, text: text, sanitizingLineBreaks: true)]
		)
	}

	func sendCTCPPing(_ nickname: String) {
		sendCTCPQuery(nickname, command: .ping, text: String(Date().timeIntervalSince1970))
	}
}
