// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

enum IdentityPolicy {
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

extension Client {
	class func account(fromWireValue value: String?) -> String? {
		IdentityPolicy.account(fromWireValue: value)
	}

	/// IRCv3 `account-notify`. A server only sends this once the capability is
	/// negotiated, so an unnegotiated one is not evidence of anything.
	func receiveAccountNotify(_ message: Message) {
		guard isCapabilityEnabled(.accountNotify) else { return }
		guard let wireAccount = message.params.first, let nickname = message.senderNickname else { return }
		let account = Self.account(fromWireValue: wireAccount)
		modifyUser(withNickname: nickname) { $0.account = account }
	}

	/// IRCv3 `setname`, gated the same way `account-notify` is.
	func receiveSetName(_ message: Message) {
		guard isCapabilityEnabled(.setName) else { return }
		guard let realName = message.params.first, let nickname = message.senderNickname else { return }
		modifyUser(withNickname: nickname) { $0.realName = realName }
	}

	/** IRCv3 `account-tag` and the ISUPPORT `BOT` token's `bot` tag.

	 Each is read under the same rule as `account-notify`: only a server that
	 negotiated the capability, or advertised the token, is saying anything by
	 sending the tag. Without that, a tag on a relayed line is whatever a
	 bouncer, a server that does not filter client tags, or the peer put there,
	 and an account name or bot flag taken from it is a claim nobody checked. */
	func updateUserIdentity(fromMessageTags message: Message) {
		guard !message.senderIsServer, let nickname = message.senderNickname, !nickname.isEmpty else { return }
		let account = isCapabilityEnabled(.accountTag) ? message.senderAccount : nil
		let isBot = supportInfo.botModeSymbol != nil && message.messageTags?["bot"] != nil
		guard account != nil || isBot else { return }

		modifyUser(withNickname: nickname) { mutableUser in
			if let account {
				mutableUser.account = IdentityPolicy.account(fromWireValue: account)
			}
			if isBot {
				mutableUser.isBot = true
			}
		}
	}

	@MainActor
	func receiveTagMessage(_ message: Message) {
		guard let target = message.params.first else { return }
		updateUserIdentity(fromMessageTags: message)

		let sender = message.senderNickname ?? ""
		let clientTags = IdentityPolicy.clientTags(from: message.messageTags ?? [:])
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

		/* Folded the way the server folds nicknames: comparing the raw strings
		 read our own TAGMSG echoed back under a different casing as somebody
		 else's and filed it in a query with ourselves. */
		let senderIsMyself = sender.isEmpty == false && nicknameIsMyself(sender)
		let channel: Channel? = if stringIsChannelName(target) {
			findChannel(target)
		} else if !sender.isEmpty, !senderIsMyself {
			findChannel(sender)
		} else if !target.isEmpty {
			findChannel(target)
		} else {
			nil
		}

		// Typing state expires against the local clock, so it is stamped with
		// the local clock too: message.receivedAt carries the server's
		// server-time tag, and any skew there makes indicators vanish
		// instantly or linger forever. Replayed history must not resurrect a
		// typing indicator at all.
		if let typing = clientTags["typing"],
		   let channel,
		   !senderIsMyself,
		   environment.preferences.displayTypingNotifications,
		   message.isHistoric == false
		{
			typingTracker.noteTypingState(
				TypingTracker.state(forTagValue: typing),
				fromNickname: sender,
				in: channel,
				at: Date()
			)
		}

		// A TAGMSG has no presentation destination until its channel or query
		// exists. In particular, typing tags must not create UI implicitly.
		guard let channel else { return }
		deliverTags(clientTags, fromSender: sender, in: channel)
		_ = shouldPrintReceivedMessage(message)
	}

	/// Hands the one client tag pair that has a destination — a reaction — to
	/// the view drawing `item`.
	@MainActor
	func deliverTags(_ clientTags: [String: String], fromSender sender: String, in item: ChatItem) {
		guard let reaction = clientTags["draft/react"], !reaction.isEmpty,
		      let reactedTo = clientTags["draft/reply"], !reactedTo.isEmpty,
		      !sender.isEmpty
		else { return }

		item.presentation?.noteReaction(reaction, fromNickname: sender, toMessageIdentifier: reactedTo)
	}
}
