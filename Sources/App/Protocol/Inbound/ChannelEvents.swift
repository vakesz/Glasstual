// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

enum InboundEventPolicy {
	static func cancelsReconnect(forError message: String) -> Bool {
		guard message.hasPrefix(ServerQuirks.LinkClosed.prefix) else { return false }
		return message.hasSuffix(ServerQuirks.LinkClosed.excessFlood)
			|| message.hasSuffix(ServerQuirks.LinkClosed.sendQueueExceeded)
	}

	static func acceptsCertificateChunk(_ data: String) -> Bool {
		(2 ... 65).contains(data.count)
	}

	/// Ceiling on the accumulated ZNC certificate chain. A full chain is a
	/// few kilobytes; without a limit the bouncer can append forever.
	static let maximumCertificateChainLength = 65536
}

private let inboundEventLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "ChannelEvents"
)

@MainActor
extension ServerSession {
	func receiveMode(_ message: Message) {
		guard message.params.count > 1, let channelName = message.params.first else { return }
		let sender = message.senderNickname ?? ""
		let modeString = message.sequence(1)

		guard stringIsChannelName(channelName) else {
			if shouldPrintReceivedCommand("UMODE", withText: modeString, destinedFor: nil, referenceMessage: message) {
				print(
					String(localized: .IRC.setsMode(sender, modeString)),
					by: nil,
					in: nil,
					as: .mode,
					command: message.command,
					receivedAt: message.receivedAt
				)
			}
			return
		}

		guard let channel = findConversation(channelName), channel.isChannel else { return }
		if !message.isPrintOnlyMessage, let modeInfo = channel.modeInfo {
			for mode in modeInfo.updateModes(modeString) where mode.isModeForChangingMemberMode(on: self) {
				guard let symbol = ChannelModeSymbol(mode.modeSymbol) else { continue }
				channel.changeMember(mode.modeParameter ?? "", mode: symbol, value: mode.modeIsSet)
			}
		}

		if shouldPrintReceivedMessage(message, withText: modeString, destinedFor: channel),
		   printsGeneralEvent(isLocalUser: false, in: channel, ignoring: nil)
		{
			print(
				String(localized: .IRC.setsMode(sender, modeString)),
				by: nil,
				in: channel,
				as: .mode,
				command: message.command,
				receivedAt: message.receivedAt
			)
		}
		if !message.isPrintOnlyMessage {
			output?.updateTitle(for: channel)
		}
	}

	func receiveTopic(_ message: Message) {
		guard message.params.count == 2,
		      let channel = findConversation(message.params[0]), channel.isChannel
		else { return }
		let topic = message.params[1]
		if !message.isPrintOnlyMessage {
			channel.topic = topic
		}
		guard shouldPrintReceivedMessage(message, withText: topic, destinedFor: channel) else { return }
		print(
			String(localized: .IRC.changedTheTopic(message.senderNickname ?? "", topic)),
			by: nil,
			in: channel,
			as: .topic,
			command: message.command, receivedAt: message.receivedAt
		)
	}

	func receiveInvite(_ message: Message) {
		guard message.params.count == 2 else { return }
		let sender = message.senderNickname ?? ""
		let invitee = message.params[0]
		let channelName = message.params[1]

		guard nicknameIsMyself(invitee) else {
			guard let channel = findConversation(channelName),
			      shouldPrintReceivedMessage(message, withText: channelName, destinedFor: channel)
			else { return }
			print(
				String(localized: .IRC.invitedToJoin(sender, invitee, channelName)),
				by: nil,
				in: channel,
				as: .invite,
				command: message.command, receivedAt: message.receivedAt
			)
			return
		}

		let text = String(localized: .IRC.invitedYouToJoin(sender, message.senderUsername ?? "", message.senderAddress ?? "", channelName))
		if shouldPrintReceivedMessage(message, withText: channelName, destinedFor: nil) {
			let selectedConversation = output?.selectedConversation(on: self)
			print(text, by: nil, in: selectedConversation, as: .invite, command: message.command,
			      receivedAt: message.receivedAt)
		}
		notifyEvent(.invite, lineType: .invite, target: nil, nickname: sender, text: channelName)
		// `JOIN 0` is the "leave every channel" form, and the invite target is
		// whatever the inviting user typed, so only real channel names may be
		// auto-joined here.
		if environment.settings.autojoinOnInvite, stringIsChannelName(channelName) {
			joinUnlistedChannel(channelName)
		}
	}

	func receiveError(_ message: Message) {
		let text = message.sequence
		if InboundEventPolicy.cancelsReconnect(forError: text) {
			addDisconnectCallback { [weak self] in self?.cancelReconnect() }
		}
		printError(text, asCommand: message.command)
	}

	func receiveCertInfo(_ message: Message) {
		guard message.params.count == 2,
		      znc.isSendingCertificateInfo,
		      message.senderIsServer,
		      message.senderNickname == ServerQuirks.ZNC.messageSender,
		      InboundEventPolicy.acceptsCertificateChunk(message.sequence),
		      let chainData = znc.certificateChainText,
		      (chainData as NSString).length < InboundEventPolicy.maximumCertificateChainLength
		else { return }
		znc.certificateChainText = chainData + "\(message.sequence)\n"
	}

	/// IRCv3 `chghost`, gated the same way `account-notify` is: a hostmask
	/// rewrite nobody negotiated is not one to believe.
	func receiveChangeHost(_ message: Message) {
		guard isCapabilityEnabled(.changeHost) else { return }
		guard message.params.count == 2, let nickname = message.senderNickname else { return }
		let username = message.params[0]
		guard username.isHostmaskUsername else {
			inboundEventLogger.error("CHGHOST contains an improperly formatted username")
			return
		}
		let address = message.params[1]
		guard address.isHostmaskAddress else {
			inboundEventLogger.error("CHGHOST contains an improperly formatted address")
			return
		}
		modifyUser(withNickname: nickname) {
			$0.username = username
			$0.address = address
		}
	}
}
