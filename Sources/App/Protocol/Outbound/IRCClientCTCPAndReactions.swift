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

/// CTCP wraps an extended message between two `0x01` bytes. ACTION is the one
/// extended message Glasstual both writes and reads, on the IRC connection and
/// on a direct chat alike, so its framing is spelled out once here instead of
/// at each of those sites.
enum CTCPPayload {
	static let delimiter = "\u{01}"

	private static let actionCommand = "ACTION"

	static func framed(command: String, text: String?, sanitizingLineBreaks: Bool) -> String {
		var payload = text.map { "\(command) \($0)" } ?? command
		if sanitizingLineBreaks {
			payload = payload.replacingOccurrences(of: "\r", with: " ")
			payload = payload.replacingOccurrences(of: "\n", with: " ")
		}
		/* modern.ircdocs.horse defines no way to quote a delimiter inside a
		 CTCP message, so one carried in the text ends the frame at the
		 receiver: everything after it is silently dropped and what follows can
		 be read as a second extended message. Removing it is the only way to
		 send the text the user actually wrote. */
		payload = payload.replacingOccurrences(of: delimiter, with: "")
		return "\(delimiter)\(payload)\(delimiter)"
	}

	static func action(_ message: String) -> String {
		framed(command: actionCommand, text: message, sanitizingLineBreaks: false)
	}

	/// The message inside an ACTION frame, or `nil` when the line is not one.
	/// A frame missing its closing delimiter still parses: some clients omit
	/// it.
	static func actionText(in line: String) -> String? {
		let prefix = "\(delimiter)\(actionCommand) "
		guard line.hasPrefix(prefix) else { return nil }
		var body = line.dropFirst(prefix.count)
		if body.hasSuffix(delimiter) {
			body = body.dropLast()
		}
		return String(body)
	}
}

public extension IRCClient {
	@MainActor
	@objc(sendReaction:toMessageIdentifier:inChannel:)
	@discardableResult
	func sendReaction(_ emoji: String, toMessageIdentifier messageIdentifier: String, in channel: IRCChannel) -> Bool {
		guard emoji.isEmpty == false, messageIdentifier.isEmpty == false, channel.isUtility == false else {
			return false
		}

		let tags = ["+draft/react": emoji, "+draft/reply": messageIdentifier]
		guard sendTagMessage(tags, toTarget: channel.name) else { return false }

		guard let treeItem = (channel as AnyObject) as? IRCTreeItem else {
			assertionFailure("IRCChannel must bridge to IRCTreeItem")
			return false
		}

		deliverTags(
			["draft/react": emoji, "draft/reply": messageIdentifier],
			fromSender: userNickname,
			toTarget: channel.name,
			in: treeItem,
			timestamp: Date(),
			messageIdentifier: nil,
			account: nil
		)
		return true
	}

	@objc(sendPrivmsg:toChannel:)
	func sendPrivmsg(_ message: String, to channel: IRCChannel) {
		sendText(NSAttributedString(string: message), as: .privmsg, to: channel)
	}

	@objc(sendAction:toChannel:)
	func sendAction(_ message: String, to channel: IRCChannel) {
		sendText(NSAttributedString(string: message), as: .privmsgAction, to: channel)
	}

	@objc(sendNotice:toChannel:)
	func sendNotice(_ message: String, to channel: IRCChannel) {
		sendText(NSAttributedString(string: message), as: .notice, to: channel)
	}

	@objc(sendPrivmsgToSelectedChannel:)
	@MainActor
	func sendPrivmsgToSelectedChannel(_ message: String) {
		guard let channel = output?.selectedChannel(on: self) else { return }
		sendPrivmsg(message, to: channel)
	}

	@objc(sendCTCPQuery:command:text:)
	func sendCTCPQuery(_ nickname: String, command: String, text: String?) {
		send(
			"PRIVMSG",
			arguments: [nickname, CTCPPayload.framed(command: command, text: text, sanitizingLineBreaks: false)]
		)
	}

	@objc(sendCTCPReply:command:text:)
	func sendCTCPReply(_ nickname: String, command: String, text: String?) {
		send(
			"NOTICE",
			arguments: [nickname, CTCPPayload.framed(command: command, text: text, sanitizingLineBreaks: true)]
		)
	}

	@objc(sendCTCPPing:)
	func sendCTCPPing(_ nickname: String) {
		sendCTCPQuery(nickname, command: "PING", text: String(Date().timeIntervalSince1970))
	}
}
