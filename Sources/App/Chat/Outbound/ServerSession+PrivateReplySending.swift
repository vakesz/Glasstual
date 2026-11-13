// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerSession {
	/// Whether a private message can carry the `channel-context` tag here.
	var canSendChannelContext: Bool {
		isCapabilityEnabled(.messageTags) && isClientTagPermitted(ChannelContextTag.outboundName)
	}

	/** Sends `text` privately to `peer`, tagged as belonging to `channel`, and
	 shows it in the channel.

	 Without the tag the peer would receive an ordinary private message while
	 the user saw it in the channel, so a server that cannot carry the tag gets
	 nothing and the user is told why. Returns whether anything was sent. */
	@discardableResult
	func sendPrivateReply(
		_ text: NSAttributedString,
		as command: RemoteCommand,
		to peer: String,
		in channel: Conversation,
		replyIdentifier: String? = nil
	) -> Bool {
		guard text.length > 0, channel.isChannel, peer.isEmpty == false,
		      stringIsChannelName(peer) == false,
		      let policy = OutboundMessageOptions(remoteCommand: command)
		else { return false }
		guard isLoggedIn else {
			printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
			return false
		}
		guard canSendChannelContext else {
			printDebugInformation(String(localized: .IRC.privateReplyNotSent), in: channel)
			return false
		}

		var replyIdentifier = replyIdentifier
		var cursor = OutboundTextCursor(text)
		enqueueOutboundText(conversations: [channel]) { session in
			guard let message = cursor.next(for: peer, on: session, as: policy.lineType) else {
				return false
			}
			let lineReplyIdentifier = replyIdentifier
			replyIdentifier = nil
			session.replies.nextPrintedLine = lineReplyIdentifier
			let deliveryLabel = session.printLocallyIfNeeded(
				message,
				in: channel,
				policy: policy,
				channelContext: channel.name,
				privatePeer: peer
			)
			session.replies.nextPrintedLine = nil

			var tags = [ChannelContextTag.outboundName: channel.name]
			if let deliveryLabel {
				tags["label"] = deliveryLabel
			}
			if let lineReplyIdentifier {
				tags["+draft/reply"] = lineReplyIdentifier
			}
			let wireMessage = policy.lineType == .action ? CTCPPayload.action(message) : message
			session.sendCommand(policy.remoteCommand, arguments: [peer, wireMessage], tags: tags)
			return true
		}
		return true
	}

	/// `/whisper <nickname> <message>`: a private message from the channel
	/// it is typed in, tagged with that channel.
	func dispatchWhisperCommand(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		var arguments = parsed.arguments
		let peer = arguments.next()
		let body = arguments.attributedRest
		guard peer.isEmpty == false, body.length > 0 else {
			printInvalidSyntaxMessage(for: parsed.command)
			return
		}
		guard let channel = targetConversation, channel.isChannel else {
			printDebugInformation(String(localized: .IRC.whisperNeedsChannel))
			return
		}
		sendPrivateReply(body, as: .privmsg, to: peer, in: channel)
	}
}
