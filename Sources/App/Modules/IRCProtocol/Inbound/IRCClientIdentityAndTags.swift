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

enum IRCIdentityPolicy {
	static func account(fromWireValue value: String?) -> String? {
		guard let value, !value.isEmpty, value != "*", value != "0" else { return nil }
		return value
	}

	static func clientTags(from tags: [String: String]) -> [String: String] {
		Dictionary(uniqueKeysWithValues: tags.compactMap { key, value in
			guard key.hasPrefix("+") else { return nil }
			return (String(key.dropFirst()), value)
		})
	}
}

private let inboundIdentityLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCInboundIdentity"
)

public extension IRCClient {
	@objc(accountFromWireValue:)
	class func account(fromWireValue value: String?) -> String? {
		IRCIdentityPolicy.account(fromWireValue: value)
	}

	@objc(receiveAccountNotify:)
	func receiveAccountNotify(_ message: Message) {
		guard let wireAccount = message.params.first, let nickname = message.senderNickname else { return }
		let account = Self.account(fromWireValue: wireAccount)
		modifyUser(withNickname: nickname) { $0.account = account }
	}

	@objc(receiveSetName:)
	func receiveSetName(_ message: Message) {
		guard let realName = message.params.first, let nickname = message.senderNickname else { return }
		modifyUser(withNickname: nickname) { $0.realName = realName }
	}

	@objc(updateUserIdentityFromMessageTags:)
	func updateUserIdentity(fromMessageTags message: Message) {
		guard !message.senderIsServer, let nickname = message.senderNickname, !nickname.isEmpty else { return }
		let account = message.senderAccount
		let isBot = message.messageTags?["bot"] != nil
		guard account != nil || isBot else { return }

		modifyUser(withNickname: nickname) { mutableUser in
			if let account {
				mutableUser.account = Self.account(fromWireValue: account)
			}
			if isBot {
				mutableUser.isBot = true
			}
		}
	}

	@MainActor
	@objc(receiveTagMessage:)
	func receiveTagMessage(_ message: Message) {
		guard let target = message.params.first else { return }
		updateUserIdentity(fromMessageTags: message)

		let sender = message.senderNickname ?? ""
		let clientTags = IRCIdentityPolicy.clientTags(from: message.messageTags ?? [:])
		guard !clientTags.isEmpty else { return }
		inboundIdentityLogger.debug("TAGMSG from \(sender, privacy: .public) to \(target, privacy: .public)")

		if let ignore = message.senderHostmask.flatMap(findAddressBookEntry(forHostmask:)) {
			if stringIsChannelName(target), ignore.ignorePublicMessages {
				return
			}
			if !stringIsChannelName(target), ignore.ignorePrivateMessages {
				return
			}
		}

		let channel: IRCChannel? = if stringIsChannelName(target) {
			findChannel(target)
		} else if !sender.isEmpty, sender != userNickname {
			findChannel(sender)
		} else if !target.isEmpty {
			findChannel(target)
		} else {
			nil
		}

		if let typing = clientTags["typing"], let channel, sender != userNickname {
			typingTracker.noteTypingState(
				IRCTypingTracker.state(forTagValue: typing),
				fromNickname: sender,
				in: channel,
				at: message.receivedAt
			)
		}

		// A TAGMSG has no presentation destination until its channel or query
		// exists. In particular, typing tags must not create UI implicitly.
		guard let channel else { return }
		let candidate: AnyObject = channel
		guard let nativeItem = candidate as? TreeItem else {
			assertionFailure("Inbound tag target must bridge to TreeItem")
			return
		}
		guard let item = (nativeItem as AnyObject) as? IRCTreeItem else {
			assertionFailure("TreeItem must bridge to IRCTreeItem")
			return
		}
		deliverTags(
			clientTags,
			fromSender: sender,
			toTarget: target,
			in: item,
			timestamp: message.receivedAt,
			messageIdentifier: message.messageIdentifier,
			account: message.senderAccount
		)
		_ = postReceivedMessage(message)
	}

	@objc(deliverClientTags:fromSender:toTarget:inItem:timestamp:messageIdentifier:account:)
	@MainActor
	func deliverTags(
		_ clientTags: [String: String],
		fromSender sender: String,
		toTarget target: String,
		in item: IRCTreeItem,
		timestamp: Date,
		messageIdentifier: String?,
		account: String?
	) {
		guard let nativeItem = (item as AnyObject) as? TreeItem else {
			assertionFailure("IRCTreeItem must bridge to TreeItem")
			return
		}

		if let reaction = clientTags["draft/react"], !reaction.isEmpty,
		   let reactedTo = clientTags["draft/reply"], !reactedTo.isEmpty,
		   !sender.isEmpty
		{
			nativeItem.viewController.noteReaction(reaction, fromNickname: sender, toMessageIdentifier: reactedTo)
		}

		let event = tagMessageEvent(
			withClientTags: clientTags,
			sender: sender,
			target: target,
			timestamp: timestamp,
			messageIdentifier: messageIdentifier,
			account: account
		)
		nativeItem.viewController.evaluateFunction(
			"_Glasstual.tagMessageReceived",
			withArguments: [event],
			onQueue: false
		)
	}

	@objc(tagMessageEventWithClientTags:sender:target:timestamp:messageIdentifier:account:)
	func tagMessageEvent(
		withClientTags clientTags: [String: String],
		sender: String,
		target: String,
		timestamp: Date,
		messageIdentifier: String?,
		account: String?
	) -> [String: Any] {
		var event: [String: Any] = [
			"sender": sender,
			"target": target,
			"tags": clientTags,
			"timestamp": timestamp.timeIntervalSince1970,
			"fromLocalUser": sender == userNickname,
			"localUserNickname": userNickname,
		]
		event["msgid"] = messageIdentifier
		event["account"] = account
		return event
	}
}
