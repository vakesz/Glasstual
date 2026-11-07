// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// What the person decided to do with pasted text the server could take as one
/// multi-line message.
enum MultilineChoice: Equatable {
	case sendAsOneMessage
	case sendFirstPart
	case sendLineByLine
	case cancel

	/// The decision a button stands for. Escape is the third button, which
	/// changes nothing.
	init(response: AlertResponse, fit: MultilineBatchPlanner.Fit) {
		switch response {
		case .default: self = fit == .fits ? .sendAsOneMessage : .sendFirstPart
		case .alternate: self = .sendLineByLine
		case .other: self = .cancel
		}
	}

	/// What happens when nobody can be asked: the lossless way.
	init(unattended fit: MultilineBatchPlanner.Fit) {
		self = fit == .fits ? .sendAsOneMessage : .sendLineByLine
	}
}

/// Pasted text cut into the lines a `draft/multiline` batch would carry, and
/// how those lines stand against the server's limits.
struct MultilineProposal {
	let lines: [MultilineWireLine]
	let limits: MultilineLimits

	var fit: MultilineBatchPlanner.Fit {
		MultilineBatchPlanner.fit(of: lines, within: limits)
	}

	/// The longest start of the text the server accepts as one message.
	var firstPart: [MultilineWireLine] {
		MultilineBatchPlanner.truncated(lines, to: limits)
	}
}

extension ServerSession {
	/// What the server lets one multi-line message hold, once the capability and
	/// the two it depends on are all in force and its value states a byte limit.
	var multilineLimits: MultilineLimits? {
		guard isCapabilityEnabled(.multiline), isCapabilityEnabled(.batch), isCapabilityEnabled(.messageTags),
		      let values = capabilityNegotiation.offeredCapabilities[MultilineLimits.capabilityName]
		else { return nil }

		return MultilineLimits(capabilityValues: values)
	}

	/** The pasted text as a batch would carry it, or `nil` when it should go the
	 usual way.

	 Only plain messages to a channel or a person qualify, and only text of two
	 or more lines. A line that starts with a single slash is a command, and a
	 command is never part of a message, so one anywhere in the text leaves the
	 whole paste to the per-line path that runs it. */
	func multilineProposal(
		for text: NSAttributedString,
		as command: RemoteCommand,
		in conversation: Conversation
	) -> MultilineProposal? {
		guard let limits = multilineLimits,
		      conversation.isConsole == false, conversation.isDirectChat == false,
		      conversation.isChannel || conversation.isDirect,
		      let policy = OutboundMessageOptions(remoteCommand: command), policy.lineType != .action
		else { return nil }

		var source = OutboundInputCursor(text)
		var lines: [MultilineWireLine] = []
		var sourceLineCount = 0

		while var line = source.next() {
			sourceLineCount += 1
			let isEscapedSlash = line.string.hasPrefix("//")

			if line.string.hasPrefix("/"), isEscapedSlash == false {
				return nil
			}

			if isEscapedSlash, line.length > 1 {
				line = line.attributedSubstring(fromIndex: 1)
			}

			guard line.length > 0 else {
				lines.append(MultilineWireLine(text: "", continuesPrevious: false))
				continue
			}

			var cursor = LineCursor(line)
			var isFirstPiece = true

			while let piece = cursor.nextLine(forTarget: conversation.name, on: self, with: policy.lineType) {
				lines.append(MultilineWireLine(text: piece, continuesPrevious: isFirstPiece == false))
				isFirstPiece = false
			}

			/* A paste this long is not a message. The per-line path asks about
			 flooding, which is the question that fits it. */
			guard lines.count <= Self.maximumMultilineWireLines else { return nil }
		}

		let trimmed = MultilineBatchPlanner.trimmingBlankEdges(lines)

		guard sourceLineCount >= 2, MultilineBatchPlanner.logicalLineCount(of: trimmed) >= 2 else { return nil }

		return MultilineProposal(lines: trimmed, limits: limits)
	}

	private static var maximumMultilineWireLines: Int {
		4096
	}

	/** Asks how the text should go out, every time it could go as one message.

	 Within the limits the choice is between one message and one per line. Over
	 them it is between the part that fits, one per line and nothing. The answer
	 acts only if the connection and the conversation are still the ones that
	 were asked about. */
	func requestMultilineChoice(
		_ proposal: MultilineProposal,
		text: NSAttributedString,
		as command: RemoteCommand,
		in conversation: Conversation,
		replyIdentifier: String?
	) {
		let fit = proposal.fit
		let startupIdentifier = startup.identifier
		let connection = socket?.uniqueIdentifier
		let destinationName = conversation.name

		let perform: @MainActor (ServerSession, MultilineChoice) -> Void = { session, choice in
			session.carryOutMultilineChoice(
				choice,
				proposal: proposal,
				text: text,
				as: command,
				in: conversation,
				replyIdentifier: replyIdentifier
			)
		}

		guard let output else {
			perform(self, MultilineChoice(unattended: fit))
			return
		}

		let request = Self.multilineChoiceAlert(for: proposal)
		output.presentAlertSheet(request) { [weak self, weak conversation] outcome in
			guard let self, let conversation, isTerminating == false,
			      startup.identifier == startupIdentifier, socket?.uniqueIdentifier == connection,
			      conversation.name == destinationName, conversationList.contains(where: { $0 === conversation })
			else { return }

			perform(self, MultilineChoice(response: outcome.response, fit: fit))
		}
	}

	func carryOutMultilineChoice(
		_ choice: MultilineChoice,
		proposal: MultilineProposal,
		text: NSAttributedString,
		as command: RemoteCommand,
		in conversation: Conversation,
		replyIdentifier: String?
	) {
		switch choice {
		case .cancel:
			break
		case .sendLineByLine:
			sendInputLines(text, as: command, destination: conversation, replyIdentifier: replyIdentifier)
		case .sendAsOneMessage:
			sendMultilineBatch(proposal.lines, as: command, to: conversation, replyIdentifier: replyIdentifier)
		case .sendFirstPart:
			let part = proposal.firstPart

			guard part.isEmpty == false else {
				sendInputLines(text, as: command, destination: conversation, replyIdentifier: replyIdentifier)
				return
			}

			sendMultilineBatch(part, as: command, to: conversation, replyIdentifier: replyIdentifier)
		}
	}

	/** Queues one `draft/multiline` batch.

	 The whole batch is written in one step of the outbound queue, so no other
	 message is put between its lines. */
	func sendMultilineBatch(
		_ lines: [MultilineWireLine],
		as command: RemoteCommand,
		to conversation: Conversation,
		replyIdentifier: String?
	) {
		guard let policy = OutboundMessageOptions(remoteCommand: command), lines.isEmpty == false else { return }

		typingSender.finish(in: conversation)
		let reply = isCapabilityEnabled(.messageTags) ? replyIdentifier : nil
		var pending: [MultilineWireLine]? = lines

		enqueueOutboundText(conversations: [conversation]) { session in
			guard let lines = pending else { return false }
			pending = nil
			session.transmitMultilineBatch(lines, policy: policy, to: conversation, replyIdentifier: reply)
			return false
		}
	}

	/** Writes `BATCH +`, one line per line of text, and `BATCH -`.

	 The label and the reply go on the opening line, which is where the message's
	 own tags belong; the lines carry only the batch reference and, for the
	 continuation of a long line, the concat tag. The message is printed once, as
	 the whole text, so the echo the server sends back and the label it carries
	 settle one line and not several. */
	private func transmitMultilineBatch(
		_ lines: [MultilineWireLine],
		policy: OutboundMessageOptions,
		to conversation: Conversation,
		replyIdentifier: String?
	) {
		let target = conversation.name
		let text = MultilineBatchPlanner.joinedText(of: lines)

		nextLineReplyToMessageIdentifier = replyIdentifier
		let deliveryLabel = printLocallyIfNeeded(
			WireRedaction.redactedServiceMessage(text, sentTo: target),
			in: conversation,
			policy: policy
		)
		nextLineReplyToMessageIdentifier = nil

		let reference = "ml" + UUID().uuidString.prefix(8).lowercased()
		var openingTags: [String: String] = [:]

		if let deliveryLabel {
			openingTags["label"] = deliveryLabel
		}

		if let replyIdentifier {
			openingTags["+draft/reply"] = replyIdentifier
		}

		sendCommand(
			.batch,
			arguments: ["+\(reference)", MultilineLimits.batchType, target],
			tags: openingTags.isEmpty ? nil : openingTags
		)

		for line in lines {
			var tags = ["batch": reference]

			if line.continuesPrevious {
				tags[MultilineLimits.concatTag] = ""
			}

			sendCommand(policy.remoteCommand, arguments: [target, line.text], tags: tags)
		}

		send(.batch, arguments: ["-\(reference)"])
	}

	private static func multilineChoiceAlert(for proposal: MultilineProposal) -> AlertRequest {
		let logicalLines = MultilineBatchPlanner.logicalLineCount(of: proposal.lines)

		switch proposal.fit {
		case .fits:
			return AlertRequest(
				title: String(localized: .MultilineSending.choiceTitle),
				body: String(localized: .MultilineSending.choiceBody(logicalLines)),
				defaultButton: String(localized: .MultilineSending.sendAsOneButton),
				alternateButton: String(localized: .MultilineSending.sendLineByLineButton),
				otherButton: PromptStrings.Action.cancel,
				cancelButton: .other
			)
		case .tooManyLines:
			return truncationAlert(body: String(localized: .MultilineSending.truncatedLinesBody(proposal.limits.maximumLines ?? 0)))
		case .tooManyBytes:
			return truncationAlert(body: String(localized: .MultilineSending.truncatedBytesBody(proposal.limits.maximumBytes)))
		}
	}

	private static func truncationAlert(body: String) -> AlertRequest {
		AlertRequest(
			title: String(localized: .MultilineSending.truncatedTitle),
			body: body,
			defaultButton: String(localized: .MultilineSending.truncateAndSendButton),
			alternateButton: String(localized: .MultilineSending.sendLineByLineButton),
			otherButton: PromptStrings.Action.cancel,
			cancelButton: .other,
			style: .warning
		)
	}
}
