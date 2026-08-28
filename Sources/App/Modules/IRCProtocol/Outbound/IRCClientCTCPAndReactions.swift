/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

enum CTCPPayload {
	static func framed(command: String, text: String?, sanitizingLineBreaks: Bool) -> String {
		var payload = text.map { "\(command) \($0)" } ?? command
		if sanitizingLineBreaks {
			payload = payload.replacingOccurrences(of: "\r", with: " ")
			payload = payload.replacingOccurrences(of: "\n", with: " ")
		}
		return "\u{01}\(payload)\u{01}"
	}
}

private enum OutboundMainQueue {
	static func sync(_ operation: @escaping @MainActor @Sendable () -> Void) {
		if Thread.isMainThread {
			MainActor.assumeIsolated(operation)
		} else {
			DispatchQueue.main.sync {
				MainActor.assumeIsolated(operation)
			}
		}
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
		OutboundMainQueue.sync { [self] in
			sendText(NSAttributedString(string: message), as: .privmsg, to: channel)
		}
	}

	@objc(sendAction:toChannel:)
	func sendAction(_ message: String, to channel: IRCChannel) {
		OutboundMainQueue.sync { [self] in
			sendText(NSAttributedString(string: message), as: .privmsgAction, to: channel)
		}
	}

	@objc(sendNotice:toChannel:)
	func sendNotice(_ message: String, to channel: IRCChannel) {
		OutboundMainQueue.sync { [self] in
			sendText(NSAttributedString(string: message), as: .notice, to: channel)
		}
	}

	@objc(sendPrivmsgToSelectedChannel:)
	@MainActor
	func sendPrivmsgToSelectedChannel(_ message: String) {
		guard let channel = NSObject.applicationController().mainWindow.selectedChannel(on: self) else { return }
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
