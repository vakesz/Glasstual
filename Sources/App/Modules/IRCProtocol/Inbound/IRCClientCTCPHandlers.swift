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
import os

enum IRCCTCPPolicy {
	static func commandAndArguments(from text: String) -> (command: String, arguments: String)? {
		// CTCP tokens are separated by SPACE (0x20), not by Unicode whitespace.
		let parts = text.unicodeScalars.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
		guard let command = parts.first, command.isEmpty == false else { return nil }
		return (String(command).uppercased(), parts.count > 1 ? String(parts[1]) : "")
	}

	static func formData(_ text: String) -> [String: String] {
		// The text is server-controlled and may repeat a key, so duplicates
		// must merge rather than trap. The first occurrence wins.
		Dictionary(
			text.split(separator: "&").compactMap { field -> (String, String)? in
				let pair = field.split(separator: "=", maxSplits: 1)
				guard pair.count == 2 else { return nil }
				return (String(pair[0]), String(pair[1]))
			},
			uniquingKeysWith: { first, _ in first }
		)
	}
}

private let ctcpLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCCTCP"
)

@MainActor
public extension IRCClient {
	@objc(receiveCTCPQuery:text:)
	func receiveCTCPQuery(_ message: Message, text: String) {
		let sender = message.senderNickname ?? ""
		let isLocalUser = nicknameIsMyself(sender)
		let ignore = isLocalUser ? nil : message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		if isLocalUser, isCapabilityEnabled(.echoMessage) {
			return
		}
		if ignore?.ignoreClientToClientProtocol == true {
			return
		}
		guard let parsed = IRCCTCPPolicy.commandAndArguments(from: text) else { return }

		if parsed.command == "LAGCHECK" {
			receiveCTCPLagCheckQuery(message, text: parsed.arguments)
			return
		}
		guard TextualPreferences.replyToCTCPRequests() else {
			printDebugInformation(toConsole: IRCCTCPStrings.ignored(command: parsed.command, sender: sender))
			return
		}
		if parsed.command == "DCC" {
			receivedDCCQuery(message, text: parsed.arguments, ignoreInfo: ignore)
			return
		}

		let printTarget = noticePrintTarget()
		print(IRCCTCPStrings.query(command: parsed.command, sender: sender), by: nil, in: printTarget, as: .ctcpQuery,
		      command: message.command, receivedAt: message.receivedAt)

		switch parsed.command {
		case "CLIENTINFO":
			sendCTCPReply(sender, command: parsed.command, text: IRCCTCPStrings.clientInfoReply)
		case "FINGER":
			sendCTCPReply(sender, command: parsed.command, text: IRCCTCPStrings.fingerReply)
		case "PING":
			guard parsed.arguments.utf8.count <= 50 else {
				ctcpLogger.fault("Ignoring PING query that exceeds 50 bytes")
				return
			}
			sendCTCPReply(sender, command: parsed.command, text: parsed.arguments)
		case "TIME":
			sendCTCPReply(sender, command: parsed.command, text: sharedISOStandardDateFormatter().string(from: Date()))
		case "USERINFO":
			sendCTCPReply(sender, command: parsed.command, text: config.realName)
		case "VERSION":
			let masquerade = config.ctcpVersionReply?.nonEmpty ?? TextualPreferences.masqueradeCTCPVersion()?.nonEmpty
			let version = masquerade ?? IRCCTCPStrings.version(
				applicationName: ApplicationInfo.applicationNameWithoutVersion(),
				shortVersion: ApplicationInfo.applicationVersionShort()
			)
			sendCTCPReply(sender, command: parsed.command, text: version)
		default:
			break
		}
	}

	@objc(receiveCTCPLagCheckQuery:text:)
	func receiveCTCPLagCheckQuery(_ message: Message, text: String) {
		guard messageIsFromMyself(message) else { return }
		let context = IRCCTCPPolicy.formData(text)
		guard let socket, context["connection"] == socket.uniqueIdentifier,
		      let time = context["time"].flatMap(Double.init)
		else { return }
		let delta = (Date().timeIntervalSince1970 - time) * 1000
		let rating = IRCCTCPStrings.lagRating(IRCCTCPLagRating(milliseconds: delta))
		let response = IRCCTCPStrings.lagCheckReply(server: serverAddress ?? "", milliseconds: delta, rating: rating)
		if let channelName = context["channel"], let channel = findChannel(channelName) {
			sendPrivmsg(response, to: channel)
		} else {
			printDebugInformation(response)
		}
	}

	@objc(receiveCTCPReply:text:)
	func receiveCTCPReply(_ message: Message, text: String) {
		if let hostmask = message.senderHostmask,
		   findAddressBookEntry(forHostmask: hostmask)?.ignoreClientToClientProtocol == true
		{
			return
		}
		guard let parsed = IRCCTCPPolicy.commandAndArguments(from: text) else { return }
		let sender = message.senderNickname ?? ""
		let output: String
		if parsed.command == "PING" {
			let delta = Date().timeIntervalSince1970 - (Double(parsed.arguments) ?? 0)
			output = IRCCTCPStrings.timedReply(sender: sender, command: parsed.command, seconds: delta)
		} else {
			output = IRCCTCPStrings.reply(sender: sender, command: parsed.command, arguments: parsed.arguments)
		}
		print(output, by: nil, in: noticePrintTarget(), as: .ctcpReply,
		      command: message.command, receivedAt: message.receivedAt)
	}

	private func noticePrintTarget() -> IRCChannel? {
		guard TextualPreferences.locationToSendNotices() == .selectedChannel else { return nil }
		return AppController.shared.mainWindow.selectedChannel(on: self)
	}
}

private extension String {
	var nonEmpty: String? {
		isEmpty ? nil : self
	}
}
