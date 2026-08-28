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

enum IRCInboundEventPolicy {
	static func cancelsReconnect(forError message: String) -> Bool {
		guard message.hasPrefix("Closing Link:") else { return false }
		return message.hasSuffix("(Excess Flood)") || message.hasSuffix("(Max SendQ exceeded)")
	}

	static func acceptsCertificateChunk(_ data: String) -> Bool {
		(2 ... 65).contains(data.count)
	}

	/// Ceiling on the accumulated ZNC certificate chain. A full chain is a
	/// few kilobytes; without a limit the bouncer can append forever.
	static let maximumCertificateChainLength = 65536

	static func shouldPrintGeneralEvent(
		showJoinLeave: Bool,
		channelIgnoresEvents: Bool
	) -> Bool {
		showJoinLeave && !channelIgnoresEvents
	}
}

private let inboundEventLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCInboundEvents"
)

@MainActor
public extension IRCClient {
	@objc(receiveMode:)
	func receiveMode(_ message: Message) {
		guard message.params.count > 1, let channelName = message.params.first else { return }
		let sender = message.senderNickname ?? ""
		let modeString = message.sequence(1)

		guard stringIsChannelName(channelName) else {
			if postReceivedCommand("UMODE", withText: modeString, destinedFor: nil, referenceMessage: message) {
				print(
					IRCInboundStrings.ChannelEvent.modeChanged(sender: sender, mode: modeString),
					by: nil,
					in: nil,
					as: .mode,
					command: message.command,
					receivedAt: message.receivedAt
				)
			}
			return
		}

		guard let channel = findChannel(channelName), channel.isChannel else { return }
		if !message.isPrintOnlyMessage, let modeInfo = channel.modeInfo {
			for mode in modeInfo.updateModes(modeString) where mode.isModeForChangingMemberMode(on: self) {
				channel.changeMember(mode.modeParameter ?? "", mode: mode.modeSymbol, value: mode.modeIsSet)
			}
		}

		if postReceivedMessage(message, withText: modeString, destinedFor: channel),
		   IRCInboundEventPolicy.shouldPrintGeneralEvent(
		   	showJoinLeave: TextualPreferences.showJoinLeave(),
		   	channelIgnoresEvents: channel.config.ignoreGeneralEventMessages
		   )
		{
			print(
				IRCInboundStrings.ChannelEvent.modeChanged(sender: sender, mode: modeString),
				by: nil,
				in: channel,
				as: .mode,
				command: message.command,
				receivedAt: message.receivedAt
			)
		}
		if !message.isPrintOnlyMessage {
			guard let item = (channel as AnyObject) as? IRCTreeItem else {
				assertionFailure("IRCChannel must bridge to IRCTreeItem")
				return
			}
			NSObject.applicationController().mainWindow.updateTitle(for: item)
		}
	}

	@objc(receiveTopic:)
	func receiveTopic(_ message: Message) {
		guard message.params.count == 2,
		      let channel = findChannel(message.params[0]), channel.isChannel
		else { return }
		let topic = message.params[1]
		if !message.isPrintOnlyMessage {
			channel.topic = topic
		}
		guard postReceivedMessage(message, withText: topic, destinedFor: channel) else { return }
		print(
			IRCInboundStrings.ChannelEvent.topicChanged(sender: message.senderNickname ?? "", topic: topic),
			by: nil,
			in: channel,
			as: .topic,
			command: message.command, receivedAt: message.receivedAt
		)
	}

	@objc(receiveInvite:)
	func receiveInvite(_ message: Message) {
		guard message.params.count == 2 else { return }
		let sender = message.senderNickname ?? ""
		let invitee = message.params[0]
		let channelName = message.params[1]

		guard nicknameIsMyself(invitee) else {
			guard let channel = findChannel(channelName),
			      postReceivedMessage(message, withText: channelName, destinedFor: channel)
			else { return }
			print(
				IRCInboundStrings.ChannelEvent.invitation(
					sender: sender,
					invitee: invitee,
					channelName: channelName
				),
				by: nil,
				in: channel,
				as: .invite,
				command: message.command, receivedAt: message.receivedAt
			)
			return
		}

		let text = IRCInboundStrings.ChannelEvent.invitation(
			sender: sender,
			username: message.senderUsername ?? "",
			address: message.senderAddress ?? "",
			channelName: channelName
		)
		if postReceivedMessage(message, withText: channelName, destinedFor: nil) {
			let channel = NSObject.applicationController().mainWindow.selectedChannel(on: self)
			print(text, by: nil, in: channel, as: .invite, command: message.command, receivedAt: message.receivedAt)
		}
		_ = notifyEvent(.invite, lineType: .invite, target: nil, nickname: sender, text: channelName)
		// `JOIN 0` is the "leave every channel" form, and the invite target is
		// whatever the inviting user typed, so only real channel names may be
		// auto-joined here.
		if TextualPreferences.autoJoinOnInvite(), stringIsChannelName(channelName) {
			joinUnlistedChannel(channelName)
		}
	}

	@objc(receiveError:)
	func receiveError(_ message: Message) {
		let text = message.sequence
		if IRCInboundEventPolicy.cancelsReconnect(forError: text) {
			disconnectCallback = { [weak self] in self?.cancelReconnect() }
		}
		printError(text, asCommand: message.command)
	}

	@objc(receiveCertInfo:)
	func receiveCertInfo(_ message: Message) {
		guard message.params.count == 2,
		      zncBouncerIsSendingCertificateInfo,
		      message.senderIsServer,
		      message.senderNickname == "znc.in",
		      IRCInboundEventPolicy.acceptsCertificateChunk(message.sequence),
		      let chainData = zncBouncerCertificateChainDataMutable,
		      chainData.length < IRCInboundEventPolicy.maximumCertificateChainLength
		else { return }
		chainData.appendFormat("%@\n", message.sequence)
	}

	@objc(receiveChangeHost:)
	func receiveChangeHost(_ message: Message) {
		guard message.params.count == 2, let nickname = message.senderNickname else { return }
		let username = message.params[0]
		guard username.isHostmaskUsername(on: self) else {
			inboundEventLogger.error("CHGHOST contains an improperly formatted username")
			return
		}
		let address = message.params[1]
		guard address.isHostmaskAddress(on: self) else {
			inboundEventLogger.error("CHGHOST contains an improperly formatted address")
			return
		}
		modifyUser(withNickname: nickname) {
			$0.username = username
			$0.address = address
		}
	}
}
