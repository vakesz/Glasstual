/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
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

enum IRCBatchPolicy {
	static let maximumParentDepth = 16

	static func normalizedToken(_ reference: String) -> (token: String, opens: Bool)? {
		guard reference.count > 1, let modifier = reference.first, modifier == "+" || modifier == "-" else {
			return nil
		}
		let token = String(reference.dropFirst())
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
		guard token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
		return (token, modifier == "+")
	}

	static func isChatHistory(_ type: String?) -> Bool {
		type == "chathistory" || type == "draft/chathistory"
	}

	static func isNetsplit(_ type: String?) -> Bool {
		type == "netsplit" || type == "netjoin"
	}

	/// A batch whose contents were said before the client asked for them:
	/// `chathistory` (IRCv3) or a bouncer's `playback` batch (ZNC).
	static func isReplay(_ type: String?) -> Bool {
		isChatHistory(type) || type == "playback" || type == "znc.in/playback"
	}
}

private let batchProcessingLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCBatchProcessing"
)

public extension IRCClient {
	@objc(queuedBatchMessageWithToken:)
	func queuedBatchMessage(withToken batchToken: String) -> Any? {
		batchMessages.queuedEntry(withBatchToken: batchToken)
	}

	@objc(filterBatchCommandIncomingData:)
	func filterBatchCommandIncomingData(_ message: Message) -> Bool {
		guard message.command.caseInsensitiveCompare("BATCH") != .orderedSame,
		      let batchToken = message.batchToken,
		      let batch = batchMessages.queuedEntry(withBatchToken: batchToken),
		      batch.batchIsOpen
		else { return false }

		// A server can nest batches arbitrarily deeply, so the walk to the
		// root is bounded rather than trusting the chain to be short.
		var rootBatch = batch
		var depth = 0
		while let parent = rootBatch.parentBatchMessage, depth < IRCBatchPolicy.maximumParentDepth {
			rootBatch = parent
			depth += 1
		}

		if rootBatch.queueEntry(message) == false {
			batchProcessingLogger.error("Dropped a message from a batch that exceeded its queue limit")
		}

		return true
	}

	@objc(receiveBatch:)
	func receiveBatch(_ message: Message) {
		guard let reference = message.params.first,
		      let tokenInfo = IRCBatchPolicy.normalizedToken(reference)
		else {
			batchProcessingLogger.error("Rejected malformed BATCH token")
			return
		}

		if tokenInfo.opens {
			openBatch(token: tokenInfo.token, message: message)
		} else {
			closeBatch(token: tokenInfo.token)
		}
	}

	@objc(recursivelyProcessBatchMessage:)
	func recursivelyProcessBatchMessage(_ batchMessage: MessageBatch) {
		recursivelyProcessBatchMessage(batchMessage, depth: 0)
	}

	@objc(recursivelyProcessBatchMessage:depth:)
	func recursivelyProcessBatchMessage(_ batchMessage: MessageBatch, depth: Int) {
		guard !batchMessage.batchIsOpen else { return }
		guard depth < IRCBatchPolicy.maximumParentDepth else {
			batchProcessingLogger.error("Refused to process a batch nested deeper than the depth limit")
			batchMessages.dequeueEntry(batchMessage)
			return
		}
		for queuedEntry in batchMessage.queuedEntries {
			switch queuedEntry {
			case let .message(message):
				processIncomingMessage(message)
			case let .batch(nestedBatch):
				recursivelyProcessBatchMessage(nestedBatch, depth: depth + 1)
			}
		}
		batchMessages.dequeueEntry(batchMessage)
	}

	@objc(batchTypeIsChatHistory:)
	func batchTypeIsChatHistory(_ batchType: String?) -> Bool {
		IRCBatchPolicy.isChatHistory(batchType)
	}

	@objc(batchTypeIsNetsplit:)
	func batchTypeIsNetsplit(_ batchType: String?) -> Bool {
		IRCBatchPolicy.isNetsplit(batchType)
	}

	@objc(batchMessageOfType:containingMessage:)
	func batchMessage(ofType batchType: String, containing message: Message) -> MessageBatch? {
		var batch = message.parentBatchMessage
		var depth = 0
		while let current = batch, depth < IRCBatchPolicy.maximumParentDepth {
			if current.batchType == batchType || current.batchType == "draft/\(batchType)" {
				return current
			}
			batch = current.parentBatchMessage
			depth += 1
		}
		return nil
	}

	@objc(channelForTargetedMessage:)
	func channel(forTargetedMessage message: Message) -> IRCChannel? {
		guard var target = message.params.first else { return nil }
		if !stringIsChannelName(target), nicknameIsMyself(target) {
			target = message.senderNickname ?? ""
		}
		guard !target.isEmpty else { return nil }
		return findChannel(target)
	}

	@objc(receiveStandardReply:)
	func receiveStandardReply(_ message: Message) {
		guard message.params.count >= 3 else { return }
		let command = message.params[0]
		let code = message.params[1]
		let description = message.params.last ?? ""
		if message.command == "FAIL", command.caseInsensitiveCompare("CHATHISTORY") == .orderedSame,
		   !noteChatHistoryFailure(message)
		{
			return
		}

		let channel: IRCChannel? = if message.params.count > 3, stringIsChannelName(message.params[2]) {
			findChannel(message.params[2])
		} else {
			nil
		}
		let text: String
		let lineType: TVCLogLineType
		switch message.command {
		case "FAIL":
			text = IRCInboundStrings.StandardReply.failure(command: command, code: code, description: description)
			lineType = .debug
		case "WARN":
			text = IRCInboundStrings.StandardReply.warning(command: command, code: code, description: description)
			lineType = .notice
		default:
			text = IRCInboundStrings.StandardReply.note(command: command, code: code, description: description)
			lineType = .notice
		}
		guard postReceivedMessage(message, withText: text, destinedFor: channel) else { return }
		print(text, by: nil, in: channel, as: lineType, command: message.command, receivedAt: message.receivedAt)
	}
}

private extension IRCClient {
	func openBatch(token: String, message: Message) {
		let batch = MessageBatch()
		batch.batchIsOpen = true
		batch.batchToken = token
		batch.batchType = message.params.count > 1 ? message.params[1] : nil
		batch.batchParameters = message.params.count > 2 ? Array(message.params.dropFirst(2)) : nil
		if let parentToken = message.batchToken {
			batch.parentBatchMessage = batchMessages.queuedEntry(withBatchToken: parentToken)
		}
		batchMessages.queueEntry(batch)

		if batch.batchType == IRCServerQuirks.ZNC.playbackBatchType {
			zncBouncerIsPlayingBackHistory = isConnectedToZNC
		} else if batch.batchType == IRCServerQuirks.ZNC.certificateInfoBatchType {
			zncBouncerIsSendingCertificateInfo = isConnectedToZNC
			if message.batchToken == nil {
				zncBouncerCertificateChainDataMutable = ""
			}
		}
	}

	func closeBatch(token: String) {
		guard let batch = batchMessages.queuedEntry(withBatchToken: token) else {
			batchProcessingLogger.error("Cannot close unknown BATCH token")
			return
		}
		batch.batchIsOpen = false
		if batch.parentBatchMessage != nil {
			batchMessages.dequeueEntry(batch)
			return
		}

		if IRCBatchPolicy.isChatHistory(batch.batchType) {
			replayChatHistoryBatch(batch)
		} else if IRCBatchPolicy.isNetsplit(batch.batchType) {
			replayNetsplitBatch(batch)
		} else {
			recursivelyProcessBatchMessage(batch)
		}

		if batch.batchType == IRCServerQuirks.ZNC.playbackBatchType {
			zncBouncerIsPlayingBackHistory = false
		} else if batch.batchType == IRCServerQuirks.ZNC.certificateInfoBatchType {
			zncBouncerIsSendingCertificateInfo = false
		}
	}
}
