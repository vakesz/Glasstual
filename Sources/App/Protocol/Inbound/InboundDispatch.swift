// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

extension Client {
	/** One line from the connection.

	 `Connection` drains the host's callbacks on the main actor in wire order
	 and only for the socket the client still owns, so a line that reaches here
	 belongs to this session and arrives in the order the server sent it. */
	func connectionDidReceive(_ data: String) {
		guard data.isEmpty == false else { return }
		processIncomingDataOnMainActor(data)
	}
}

/// `Client.processIncomingMessage` is the overridable seam in front of this,
/// which is why the dispatch entry point is separate from the handlers below.
@MainActor
extension Client {
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
}

private extension Client {
	func processIncomingDataOnMainActor(_ data: String) {
		guard isConnected, !isTerminating else { return }
		lastMessageReceived = Date().timeIntervalSince1970
		clientDirectory?.noteMessageReceived(length: UInt(data.utf16.count))
		rawDataLogIncomingTraffic(data)

		/* The line is parsed as it arrived. "Remove formatting" is about what the
		 transcript shows, and it is applied where a line is printed: stripping
		 the raw line took control codes out of channel names, tags and CTCP
		 arguments too, which then named things the server had never sent. */
		guard var message = Message(line: data, on: self),
		      let interceptedMessage = interceptZNCServerInput(message)
		else { return }
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
		guard let command = RemoteCommand(wireName: message.command) else {
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

enum BatchPolicy {
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

extension Client {
	func queuedBatchMessage(withToken batchToken: String) -> Any? {
		batchMessages.queuedEntry(withBatchToken: batchToken)
	}

	func filterBatchCommandIncomingData(_ message: Message) -> Bool {
		guard message.command.caseInsensitiveCompare("BATCH") != .orderedSame,
		      let batchToken = message.batchToken,
		      let batch = batchMessages.queuedEntry(withBatchToken: batchToken),
		      batch.batchIsOpen
		else { return false }

		let rootBatch = batch.rootBatch

		guard rootBatch.hasOverflowed == false else {
			return false
		}

		if rootBatch.queueMessage(message) {
			return true
		}

		/* A full queue used to drop the message, so a netsplit wider than the
		 queue lost the QUITs past it and left those people listed in every
		 channel. What was queued is processed now, in order, and the rest of
		 the batch as it arrives: the batch loses its replay treatment, but no
		 line. Its labelled response, if any, can no longer be trusted. */
		rootBatch.hasOverflowed = true
		rootBatch.deliveryState = .failed
		batchProcessingLogger.error("A batch exceeded its queue limit; processing the rest of it as it arrives")

		let queued = rootBatch.queuedMessages
		rootBatch.dequeueMessages()
		for queuedMessage in queued {
			processIncomingMessage(queuedMessage)
		}

		return false
	}

	func receiveBatch(_ message: Message) {
		guard let reference = message.params.first,
		      let tokenInfo = BatchPolicy.normalizedToken(reference)
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

	/// Processes the messages a closed batch held back, in the order they
	/// arrived, and retires the batch.
	func processQueuedMessages(of batchMessage: MessageBatch) {
		guard !batchMessage.batchIsOpen else { return }
		for message in batchMessage.queuedMessages {
			processIncomingMessage(message)
		}
		batchMessages.dequeueEntry(batchMessage)
	}

	func batchMessage(ofType batchType: String, containing message: Message) -> MessageBatch? {
		var batch = message.parentBatchMessage
		var depth = 0
		while let current = batch, depth < BatchPolicy.maximumParentDepth {
			if current.batchType == batchType || current.batchType == "draft/\(batchType)" {
				return current
			}
			batch = current.parentBatchMessage
			depth += 1
		}
		return nil
	}

	func channel(forTargetedMessage message: Message) -> Channel? {
		guard var target = message.params.first else { return nil }
		if !stringIsChannelName(target), nicknameIsMyself(target) {
			target = message.senderNickname ?? ""
		}
		guard !target.isEmpty else { return nil }
		return findChannel(target)
	}

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

		let channel: Channel? = if message.params.count > 3, stringIsChannelName(message.params[2]) {
			findChannel(message.params[2])
		} else {
			nil
		}
		let text: String
		let lineType: LogLineType
		switch message.command {
		case "FAIL":
			text = String(localized: .IRC.standardRepliesFailWarn(command, code, description))
			lineType = .debug
		case "WARN":
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

private extension Client {
	func openBatch(token: String, message: Message) {
		let batch = MessageBatch()
		batch.batchIsOpen = true
		batch.batchToken = token
		batch.batchType = message.params.count > 1 ? message.params[1] : nil
		batch.batchParameters = message.params.count > 2 ? Array(message.params.dropFirst(2)) : nil
		if let parentToken = message.batchToken {
			guard let parent = batchMessages.queuedEntry(withBatchToken: parentToken),
			      parent.batchIsOpen else { return }
			var ancestor: MessageBatch? = parent
			var depth = 1
			while let current = ancestor {
				depth += 1
				guard depth <= BatchPolicy.maximumParentDepth else { return }
				ancestor = current.parentBatchMessage
			}
			batch.parentBatchMessage = parent
		}

		guard batchMessages.queueEntry(batch) else {
			batchProcessingLogger.error("Refused a duplicate BATCH token or a batch past the open-batch limit")
			return
		}

		if batch.batchType == ServerQuirks.ZNC.playbackBatchType {
			znc.isPlayingBackHistory = znc.isConnected
		} else if batch.batchType == ServerQuirks.ZNC.certificateInfoBatchType {
			znc.isSendingCertificateInfo = znc.isConnected
			if message.batchToken == nil {
				znc.certificateChainText = ""
			}
		}
		if isCapabilityEnabled(.labeledResponse), let label = message.messageTags?["label"], !label.isEmpty {
			batch.responseLabel = label
		}
		associateServerHistoryRequest(with: batch)
	}

	func closeBatch(token: String) {
		guard let batch = batchMessages.queuedEntry(withBatchToken: token) else {
			batchProcessingLogger.error("Cannot close unknown BATCH token")
			return
		}
		batch.batchIsOpen = false
		if batch.parentBatchMessage != nil {
			// Keep closed children admitted until the root replays. Messages retain
			// their immediate batch, whose parent and label must still be available.
			return
		}

		let family = batchMessages.queuedEntries.values.filter { $0.rootBatch === batch }
		let incomplete = batch.deliveryState == .failed || family.contains { $0.batchIsOpen }

		replay(batch, family: family)
		resolveDeliveries(in: family, incomplete: incomplete)
		endZNCPlaybackState(for: batch)
	}

	/// Hands the closed batch to whichever replay owns its type. A labelled
	/// response wrapping exactly one chat-history batch is that history page,
	/// so the wrapper's contents are what gets replayed.
	private func replay(_ batch: MessageBatch, family: [MessageBatch]) {
		let historyBatches = family.filter { BatchPolicy.isChatHistory($0.batchType) }
		let nestedHistory = historyBatches.first { $0.parentBatchMessage != nil }

		if let nestedHistory, historyBatches.count == 1 {
			replayChatHistoryBatch(nestedHistory, contents: batch)
		} else if BatchPolicy.isChatHistory(batch.batchType) {
			replayChatHistoryBatch(batch)
		} else if BatchPolicy.isNetsplit(batch.batchType) {
			replayNetsplitBatch(batch)
		} else {
			processQueuedMessages(of: batch)
		}
	}

	/** Answers every labelled member of the family and empties the queue.

	 A batch's final result is known only after every queued reply ran: in
	 particular an echo before FAIL must not commit success early, which is why
	 `incomplete` is settled by the caller rather than in here. The failures go
	 first because a label two members share resolves once, and the dictionary
	 the family came out of has no order of its own. */
	private func resolveDeliveries(in family: [MessageBatch], incomplete: Bool) {
		let failuresFirst = family.sorted { first, second in
			first.deliveryState == .failed && second.deliveryState != .failed
		}

		for member in failuresFirst {
			if let label = member.responseLabel {
				let memberFailed = incomplete || member.deliveryState == .failed
				resolveDelivery(
					withLabel: label,
					state: incomplete ? .failed : member.deliveryState,
					messageIdentifier: memberFailed ? nil : member.deliveryMessageIdentifier,
					reason: member.deliveryFailureReason
				)
			}
			batchMessages.dequeueEntry(member)
		}
	}

	private func endZNCPlaybackState(for batch: MessageBatch) {
		if batch.batchType == ServerQuirks.ZNC.playbackBatchType {
			znc.isPlayingBackHistory = false
		} else if batch.batchType == ServerQuirks.ZNC.certificateInfoBatchType {
			znc.isSendingCertificateInfo = false
		}
	}
}
