/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import CocoaExtensions
import Foundation

enum IRCClientHistoricMessagePolicy {
	static func shouldAdvanceServerTime(
		isLoggedIn: Bool,
		isHistoric: Bool,
		receivedTime: TimeInterval,
		lastServerTime: TimeInterval
	) -> Bool {
		isLoggedIn && isHistoric && receivedTime > lastServerTime
	}

	static func shouldMarkCurrent(
		playbackCapabilityEnabled: Bool,
		isContainedInChatHistoryBatch: Bool
	) -> Bool {
		playbackCapabilityEnabled && !isContainedInChatHistoryBatch
	}
}

public extension IRCClient {
	@objc(ircConnection:didReceiveData:)
	func ircConnection(_ sender: Connection, didReceiveData data: String) {
		guard !data.isEmpty else { return }
		/* The connection delivers its callbacks on the main actor in wire order,
		 so a line can only ever arrive for the socket the client still owns. */
		guard sender === socket else { return }
		processIncomingDataOnMainActor(data)
	}

	@objc(processIncomingMessage:)
	func processIncomingMessage(_ message: Message) {
		processIncomingMessageOnMainActor(message)
	}
}

private extension IRCClient {
	func processIncomingDataOnMainActor(_ data: String) {
		guard isConnected, !isTerminating else { return }
		lastMessageReceived = Date().timeIntervalSince1970
		AppController.shared.world.noteMessageReceived(length: UInt(data.utf16.count))
		rawDataLogIncomingTraffic(data)

		let normalizedData = TextualPreferences.removeAllFormatting() ? (data as NSString).stripIRCEffects : data
		guard var message = Message(line: normalizedData, on: self),
		      let interceptedMessage = PluginDispatcher.interceptServerInput(message, for: self)
		else { return }
		message = interceptedMessage
		guard !filterBatchCommandIncomingData(message) else { return }
		processIncomingMessageOnMainActor(message)
	}

	func processIncomingMessageAttributes(_ message: Message) {
		let receivedTime = message.receivedAt.timeIntervalSince1970
		guard IRCClientHistoricMessagePolicy.shouldAdvanceServerTime(
			isLoggedIn: isLoggedIn,
			isHistoric: message.isHistoric,
			receivedTime: receivedTime,
			lastServerTime: lastMessageServerTime
		) else { return }

		lastMessageServerTime = receivedTime
		let containedInChatHistory = batchMessage(ofType: "chathistory", containing: message) != nil
		if IRCClientHistoricMessagePolicy.shouldMarkCurrent(
			playbackCapabilityEnabled: isCapabilityEnabled(.playback),
			isContainedInChatHistoryBatch: containedInChatHistory
		) {
			message.markAsNotHistoric()
		}
	}

	func processIncomingMessageOnMainActor(_ message: Message) {
		processIncomingMessageAttributes(message)
		if resolveLabeledResponse(for: message) {
			processBundlesServerMessage(message)
			return
		}

		if message.commandNumeric > 0 {
			receiveNumericReply(message)
		} else {
			dispatchRemoteCommand(message)
		}
		processBundlesServerMessage(message)
	}

	func dispatchRemoteCommand(_ message: Message) {
		guard let command = IRCRemoteCommand(rawValue: CommandIndex.index(ofRemoteCommand: message.command)) else {
			return
		}
		if dispatchCoreRemoteCommand(command, message: message) {
			return
		}
		dispatchExtendedRemoteCommand(command, message: message)
	}

	func dispatchCoreRemoteCommand(_ command: IRCRemoteCommand, message: Message) -> Bool {
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

	func dispatchExtendedRemoteCommand(_ command: IRCRemoteCommand, message: Message) {
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
