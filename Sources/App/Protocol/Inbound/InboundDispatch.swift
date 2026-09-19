// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension ServerSession {
	/** One line from the connection.

	 `Connection` drains the host's callbacks on the main actor in wire order
	 and only for the socket the session still owns, so a line that reaches here
	 belongs to this session and arrives in the order the server sent it. */
	func connectionDidReceive(_ data: String) {
		guard data.isEmpty == false else { return }
		processIncomingDataOnMainActor(data)
	}

	/// The five facts the wire parser reads a line against. The one place this
	/// session's state is handed to the parser.
	var messageParsingContext: MessageParsingContext {
		MessageParsingContext(
			serverAddress: serverAddress ?? "",
			maximumNicknameLength: maximumHostmaskNicknameLength(on: self),
			batchEnabled: isCapabilityEnabled(.batch),
			serverTimeEnabled: isCapabilityEnabled(.serverTime),
			isKnownBouncer: znc.isConnected
		)
	}
}

/// `ServerSession.processIncomingMessage` is the overridable seam in front of this,
/// which is why the dispatch entry point is separate from the handlers below.
@MainActor
extension ServerSession {
	func processIncomingMessageOnMainActor(_ message: Message) {
		processIncomingMessageAttributes(message)
		if resolveLabeledResponse(for: message) {
			handleZNCStatusNotice(message)
			return
		}

		if message.commandNumeric > 0 {
			receiveNumericReply(message)
		} else {
			dispatchRemoteCommand(message)
		}
		handleZNCStatusNotice(message)
	}

	/// The numeric arm of the dispatch above: an error reply, one of the five
	/// groups a known numeric belongs to, or a reply this session only prints.
	func receiveNumericReply(_ message: Message) {
		let rawNumeric = message.commandNumeric

		if ServerNumeric.isErrorReply(rawNumeric) {
			receiveErrorNumericReply(message)
			return
		}

		let numeric = ServerNumeric(rawValue: rawNumeric)
		let shouldPrint = numeric?.requiresSpecialFiltering == true || shouldPrintReceivedMessage(message)

		if let numeric, let group = numeric.group {
			switch group {
			case .connection:
				handleConnectionNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .whois:
				handleWhoisNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .channel:
				handleChannelNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .presence:
				handlePresenceTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint)
			case .authentication:
				handleAuthenticationTrackingNumeric(numeric, message: message, shouldPrint: shouldPrint)
			}

			return
		}

		guard shouldPrint else { return }
		if inWhoisResponse, message.params.count > 2 {
			printReply(message, in: output?.selectedConversation(on: self))
		} else {
			printReply(message)
		}
	}
}

private extension ServerSession {
	func processIncomingDataOnMainActor(_ data: String) {
		guard isConnected, !isTerminating else { return }
		lastMessageReceived = Date().timeIntervalSince1970
		chatSession?.noteMessageReceived(length: UInt(data.utf16.count))
		rawDataLogIncomingTraffic(data)

		/* The line is parsed as it arrived. "Remove formatting" is about what the
		 transcript shows, and it is applied where a line is printed: stripping
		 the raw line took control codes out of channel names, tags and CTCP
		 arguments too, which then named things the server had never sent. */
		guard var message = Message(line: data, context: messageParsingContext) else { return }
		resolveBatch(of: &message)
		guard let interceptedMessage = interceptZNCServerInput(message) else { return }
		message = interceptedMessage
		guard !filterBatchCommandIncomingData(message) else { return }
		processIncomingMessageOnMainActor(message)
	}

	/** The stored server time is the point a bouncer replays from, so it tracks
	 the newest stamp seen, live or replayed. Whether the line itself is replay
	 was decided when it was parsed. */
	func processIncomingMessageAttributes(_ message: Message) {
		let receivedTime = message.receivedAt.timeIntervalSince1970

		guard isLoggedIn, message.hasServerTime, receivedTime > lastMessageServerTime else { return }

		lastMessageServerTime = receivedTime
	}

	func dispatchRemoteCommand(_ message: Message) {
		guard let command = message.remoteCommand else {
			return
		}
		if dispatchCoreRemoteCommand(command, message: message) {
			return
		}
		dispatchExtendedRemoteCommand(command, message: message)
	}

	func dispatchCoreRemoteCommand(_ command: RemoteCommand, message: Message) -> Bool {
		switch command {
		case .notice, .privmsg:
			receivePrivmsgAndNotice(message)
		case .error:
			receiveError(message)
		case .invite:
			receiveInvite(message)
		case .join:
			receiveJoin(message)
		case .kick:
			receiveKick(message)
		case .kill:
			receiveKill(message)
		case .mode:
			receiveMode(message)
		case .nick:
			receiveNick(message)
		case .part:
			receivePart(message)
		case .ping:
			receivePing(message)
		case .quit:
			receiveQuit(message)
		case .topic:
			receiveTopic(message)
		case .wallops:
			receiveWallops(message)
		default:
			return false
		}
		return true
	}

	func dispatchExtendedRemoteCommand(_ command: RemoteCommand, message: Message) {
		switch command {
		case .authenticate, .cap:
			detectZNC(from: message)
			handleCapabilityOrAuthenticationRequest(message)
		case .away:
			receiveAwayNotifyCapability(message)
		case .batch:
			receiveBatch(message)
		case .certinfo:
			receiveCertInfo(message)
		case .chghost:
			receiveChangeHost(message)
		case .account:
			receiveAccountNotify(message)
		case .setname:
			receiveSetName(message)
		case .tagmsg:
			receiveTagMessage(message)
		case .fail, .warn, .note:
			receiveStandardReply(message)
		case .markread:
			receiveReadMarker(message)
		default:
			break
		}
	}
}

@MainActor
extension ServerSession {
	func conversation(forTargetedMessage message: Message) -> Conversation? {
		guard var target = message.params.first else { return nil }
		if !stringIsChannelName(target), nicknameIsMyself(target) {
			target = message.senderNickname ?? ""
		}
		guard !target.isEmpty else { return nil }
		return findConversation(target)
	}

	func receiveStandardReply(_ message: Message) {
		guard message.params.count >= 3 else { return }
		let command = message.params[0]
		let code = message.params[1]
		let description = message.params.last ?? ""
		if message.remoteCommand == .fail, RemoteCommand(wireName: command) == .chathistory,
		   !noteChatHistoryFailure(message)
		{
			return
		}

		let channel: Conversation? = if message.params.count > 3, stringIsChannelName(message.params[2]) {
			findConversation(message.params[2])
		} else {
			nil
		}
		let text: String
		let lineType: ChatLineKind
		switch message.remoteCommand {
		case .fail:
			text = String(localized: .IRC.standardRepliesFailWarn(command, code, description))
			lineType = .debug
		case .warn:
			text = String(localized: .IRC.warn(command, code, description))
			lineType = .notice
		default:
			text = String(localized: .IRC.standardRepliesFailWarnNote(command, code, description))
			lineType = .notice
		}
		guard shouldPrintReceivedMessage(message, withText: text, destinedFor: channel) else { return }
		print(text, by: nil, in: channel, as: lineType, command: message.command, receivedAt: message.receivedAt)
	}
}
