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
import GlasstualPluginKit

enum IRCInboundTextPolicy {
	struct Classification {
		let text: String
		let lineType: TVCLogLineType
	}

	static func classify(command: String, payload: String) -> Classification {
		let isPrivmsg = command == "PRIVMSG"
		guard payload.hasPrefix("\u{1}") else {
			return Classification(text: payload, lineType: isPrivmsg ? .privateMessage : .notice)
		}
		var text = String(payload.dropFirst())
		if let close = text.firstIndex(of: "\u{1}") {
			text = String(text[..<close])
		}
		if isPrivmsg, text.lowercased().hasPrefix("action ") {
			return Classification(text: String(text.dropFirst(7)), lineType: .action)
		}
		return Classification(text: text, lineType: isPrivmsg ? .ctcpQuery : .ctcpReply)
	}

	static func lineType(_ lineType: TVCLogLineType, suppressingHighlights: Bool) -> TVCLogLineType {
		guard suppressingHighlights else { return lineType }
		switch lineType {
		case .action: return .actionNoHighlight
		case .privateMessage: return .privateMessageNoHighlight
		default: return lineType
		}
	}
}

enum IRCServiceNoticePolicy {
	struct ChannelNotice {
		let channelName: String
		let text: String
	}

	enum NickServAction: Equatable {
		case sendIdentification(target: String, text: String)
		case identificationSucceeded
	}

	struct NickServContext {
		let isWaiting: Bool
		let password: String?
		let nickname: String
		let serverAddress: String?
		let sendsAuthenticationToUserServ: Bool
		let needsIdentificationTokens: [String]
		let successfulIdentificationTokens: [String]
	}

	/// Whether a `NickServ` notice plausibly came from network services.
	///
	/// The reply to one of these carries the account password. Nothing stops
	/// an ordinary user from holding the nickname `NickServ` on a network
	/// without nickname protection, so the sender has to look like a service
	/// before anything is sent back.
	static func noticeIsFromServices(
		senderIsServer: Bool,
		senderAddress: String?,
		serverAddress: String?
	) -> Bool {
		if senderIsServer {
			return true
		}

		guard let address = senderAddress?.lowercased(), address.isEmpty == false else {
			return false
		}

		if address == "services." || address.hasPrefix("services.") || address.contains(".services.") {
			return true
		}

		/* Some networks host services under the network's own domain, as in
		 NickServ!service@dal.net against irc.dal.net. */
		guard let serverAddress = serverAddress?.lowercased(), serverAddress.isEmpty == false else {
			return false
		}

		return address == serverAddress || serverAddress.hasSuffix("." + address)
	}

	static func channelNotice(from text: String) -> ChannelNotice? {
		guard text.hasPrefix("["), let space = text.firstIndex(of: " ") else { return nil }
		let head = text[..<space]
		guard head.count >= 4, head.hasSuffix("]") else { return nil }
		return ChannelNotice(
			channelName: String(head.dropFirst().dropLast()),
			text: String(text[text.index(after: space)...])
		)
	}

	static func nickServAction(for text: String, context: NickServContext) -> NickServAction? {
		if context.isWaiting {
			guard context.successfulIdentificationTokens.contains(where: text.localizedCaseInsensitiveContains) else {
				return nil
			}
			return .identificationSucceeded
		}

		guard let password = context.password, !password.isEmpty,
		      context.needsIdentificationTokens.contains(where: text.localizedCaseInsensitiveContains)
		else { return nil }
		if context.serverAddress?.hasSuffix(".dal.net") == true {
			return .sendIdentification(target: "NickServ@services.dal.net", text: "IDENTIFY \(password)")
		}
		if context.sendsAuthenticationToUserServ {
			return .sendIdentification(target: "userserv", text: "login \(context.nickname) \(password)")
		}
		return .sendIdentification(target: "NickServ", text: "IDENTIFY \(password)")
	}
}

@MainActor
public extension IRCClient {
	@objc(receiveWallops:)
	func receiveWallops(_ message: Message) {
		guard let payload = message.params.first else { return }
		let rewritten = message.duplicate()
		rewritten.command = "NOTICE"
		rewritten.params = [
			userNickname,
			String(format: TVCLogLineSpecialNoticeMessageFormat, message.command, payload),
		]
		receivePrivmsgAndNotice(rewritten)
	}

	@objc(receivePrivmsgAndNotice:)
	func receivePrivmsgAndNotice(_ message: Message) {
		guard message.params.count > 1 else { return }
		updateUserIdentity(fromMessageTags: message)
		let result = IRCInboundTextPolicy.classify(command: message.command, payload: message.params[1])
		switch result.lineType {
		case .action, .privateMessage, .notice:
			receiveText(message, lineType: result.lineType, text: result.text)
		case .ctcpQuery:
			receiveCTCPQuery(message, text: result.text)
		case .ctcpReply:
			receiveCTCPReply(message, text: result.text)
		default:
			break
		}
	}

	@objc(receiveText:lineType:text:)
	func receiveText(_ message: Message, lineType originalLineType: TVCLogLineType, text originalText: String) {
		guard message.params.count > 1 else { return }
		var text = originalText
		if text.isEmpty {
			guard originalLineType == .action || originalLineType == .actionNoHighlight else { return }
			text = " "
		}
		var target = message.params[0]
		guard !target.isEmpty else { return }
		if supportInfo.extractStatusMessagePrefix(fromChannelNamed: target).count == 1 {
			target.removeFirst()
		}

		let ignore = message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:))
		let lineType = IRCInboundTextPolicy.lineType(
			originalLineType, suppressingHighlights: ignore?.ignorePublicMessageHighlights ?? false
		)
		if lineType == .notice, ignore?.ignoreNoticeMessages == true {
			return
		}

		if stringIsChannelName(target) {
			guard ignore?.ignorePublicMessages != true else { return }
			receivePublicText(message, lineType: lineType, target: target, text: text)
		} else if !message.senderIsServer {
			guard ignore?.ignorePrivateMessages != true else { return }
			receivePrivateText(message, lineType: lineType, target: target, text: text)
		} else {
			receiveServerText(message, lineType: lineType, target: target, text: text)
		}
	}

	private func receivePublicText(
		_ message: Message, lineType: TVCLogLineType, target: String, text: String
	) {
		guard let channel = findChannel(target) else { return }
		let sender = message.senderNickname ?? ""
		let isSelfMessage = isCapabilityEnabled(.echoMessage) && nicknameIsMyself(sender)
		let isNotice = lineType == .notice
		let completion: LogControllerPrintOperationCompletion = { [weak self, weak channel] context in
			guard let self, let channel, !isSelfMessage else { return }
			if isNotice {
				if isSafeToPostNotification(for: message, in: channel) {
					_ = notifyText(.channelNotice, lineType: lineType, target: channel, nickname: sender, text: text)
				}
				return
			}
			let highlight = context.isHighlight
			var postEvent = true
			if isSafeToPostNotification(for: message, in: channel) {
				postEvent = notifyText(
					highlight ? .highlight : .channelMessage,
					lineType: lineType, target: channel, nickname: sender, text: text
				)
			}
			guard postEvent else { return }
			if highlight {
				setHighlightState(for: channel)
			}
			setUnreadState(for: channel, isHighlight: highlight)
		}

		if dispatchTextThroughPlugins(text, message: message, destination: channel, lineType: lineType) {
			print(text, by: sender, in: channel, as: lineType, command: message.command,
			      receivedAt: message.receivedAt, isEncrypted: false, referenceMessage: message,
			      completionBlock: completion)
		}
		guard !isNotice, let member = channel.memberInfo?.findMember(sender) else { return }
		let localNickname = userNickname.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
		if text.localizedCaseInsensitiveContains(localNickname) {
			member.outgoingConversation()
		} else {
			member.conversation()
		}
	}

	private func receivePrivateText(
		_ message: Message, lineType: TVCLogLineType, target: String, text: String
	) {
		let sender = message.senderNickname ?? ""
		let isNotice = lineType == .notice
		let isSelfMessage =
			(isCapabilityEnabled(.echoMessage) || isCapabilityEnabled(.zncSelfMessage) || isConnectedToZNC)
				&& nicknameIsMyself(sender)
		var query = findChannel(isSelfMessage ? target : sender)
		var deliveredText = text
		var newPrivateMessage = false

		if isNotice {
			if sender.caseInsensitiveCompare("ChanServ") == .orderedSame {
				(query, deliveredText) = channelServiceNoticeDestination(current: query, text: text)
			} else if sender.caseInsensitiveCompare("NickServ") == .orderedSame {
				processNickServNotice(text, from: message)
			}
			if TextualPreferences.locationToSendNotices() == .selectedChannel {
				query = AppController.shared.mainWindow.selectedChannel(on: self)
			}
			if query == nil, TextualPreferences.locationToSendNotices() == .query {
				query = findChannelOrCreate(isSelfMessage ? target : sender, as: .privateMessage)
			}
		} else if query == nil {
			newPrivateMessage = true
			query = findChannelOrCreate(isSelfMessage ? target : sender, as: .privateMessage)
		}
		let textToDeliver = deliveredText

		let completion: LogControllerPrintOperationCompletion = { [weak self, weak query] context in
			guard let self, !isSelfMessage else { return }
			let highlight = context.isHighlight
			var postEvent = true
			if isSafeToPostNotification(for: message, in: query) {
				let event: TXNotificationType = isNotice ? .privateNotice
					: (highlight ? .highlight : (newPrivateMessage ? .newPrivateMessage : .privateMessage))
				if let query {
					postEvent = notifyText(
						event,
						lineType: lineType,
						target: query,
						nickname: sender,
						text: textToDeliver
					)
				}
			}
			guard postEvent, let query else { return }
			if highlight {
				setHighlightState(for: query)
			}
			setUnreadState(for: query, isHighlight: highlight)
		}

		if dispatchTextThroughPlugins(textToDeliver, message: message, destination: query, lineType: lineType) {
			print(textToDeliver, by: sender, in: query, as: lineType, command: message.command,
			      receivedAt: message.receivedAt, isEncrypted: false, referenceMessage: message,
			      completionBlock: completion)
		}
		if !isNotice, let query, !query.isActive {
			query.activate()
			if let item = (query as AnyObject) as? IRCTreeItem {
				AppController.shared.mainWindow.reloadTreeItem(item)
			}
		}
	}

	private func receiveServerText(
		_ message: Message, lineType: TVCLogLineType, target _: String, text: String
	) {
		let sender = message.senderNickname ?? ""
		let query = lineType == .notice ? findChannel(sender) : findChannelOrCreate(sender, as: .privateMessage)
		if dispatchTextThroughPlugins(text, message: message, destination: query, lineType: lineType) {
			print(text, by: sender, in: query, as: lineType, command: message.command,
			      receivedAt: message.receivedAt, isEncrypted: false, referenceMessage: message)
		}
		if sender.hasSuffix(IRCServerQuirks.Proxy.nicknameSuffix),
		   text == IRCServerQuirks.Proxy.connectedMessage
		{
			addDisconnectCallback { [weak self] in
				self?.printDebugInformation(toConsole: IRCConnectionStrings.reconnectingToProxy)
				self?.connect(.reconnect)
			}
			disconnect()
		}
	}

	private func channelServiceNoticeDestination(
		current: IRCChannel?, text: String
	) -> (IRCChannel?, String) {
		guard let notice = IRCServiceNoticePolicy.channelNotice(from: text),
		      stringIsChannelName(notice.channelName),
		      let channel = findChannel(notice.channelName)
		else { return (current, text) }
		return (channel, notice.text)
	}

	private func processNickServNotice(_ text: String, from message: Message) {
		guard IRCServiceNoticePolicy.noticeIsFromServices(
			senderIsServer: message.senderIsServer,
			senderAddress: message.senderAddress,
			serverAddress: serverAddress
		) else {
			return
		}

		serverHasNickServ = true
		let comparableText = TextualPreferences.removeAllFormatting() ? text : (text as NSString).stripIRCEffects
		let action = IRCServiceNoticePolicy.nickServAction(
			for: comparableText,
			context: .init(
				isWaiting: isWaitingForNickServ,
				password: config.nicknamePassword,
				nickname: config.nickname,
				serverAddress: serverAddress,
				sendsAuthenticationToUserServ: config.sendAuthenticationRequestsToUserServ,
				needsIdentificationTokens: nickServNeedIdentificationTokens,
				successfulIdentificationTokens: nickServSuccessfulIdentificationTokens
			)
		)
		switch action {
		case let .sendIdentification(target, text):
			send("PRIVMSG", arguments: [target, text])
			isWaitingForNickServ = true
			userIsIdentifiedWithNickServ = false
		case .identificationSucceeded:
			isWaitingForNickServ = false
			userIsIdentifiedWithNickServ = true
			if config.autojoinWaitsForNickServ {
				performAutoJoin()
			}
		case nil:
			break
		}
	}

	private func dispatchTextThroughPlugins(
		_ text: String,
		message: Message,
		destination: IRCChannel?,
		lineType: TVCLogLineType
	) -> Bool {
		let author = message.sender
		return PluginDispatcher.dispatchReceivedText(
			text,
			authoredBy: author,
			destinedFor: destination,
			as: lineType,
			onClient: self,
			receivedAt: message.receivedAt,
			wasEncrypted: false
		)
	}
}
