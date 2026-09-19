// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What the printing path tells a caller once the line it asked for is on
/// screen. The transcript satisfies this; the domain declares it.
typealias PrintedLineCompletion = (PrintedLineContext) -> Void

/** What a caller's completion block is told about the line it printed.

 A value, and only ever read: the session and the conversation are weak because
 the completion may run after either has been torn down, and everything else is
 the rendered outcome the caller asked to hear about. */
struct PrintedLineContext {
	private(set) weak var session: ServerSession?
	private(set) weak var conversation: Conversation?
	let isHighlight: Bool
	let chatLine: ChatLine
	let lineNumber: String
	var isDuplicate = false
	var isDisplayed = true

	init(session: ServerSession, conversation: Conversation?, highlight: Bool, chatLine: ChatLine, lineNumber: String) {
		self.session = session
		self.conversation = conversation
		isHighlight = highlight
		self.chatLine = chatLine
		self.lineNumber = lineNumber
	}
}

/// Everything a caller decides about one line, gathered so that the printing
/// path takes one argument rather than ten.
struct LinePrintRequest {
	let messageBody: String
	let nickname: String?
	let conversation: Conversation?
	let lineType: ChatLineKind
	let command: String?
	let receivedAt: Date
	let isEncrypted: Bool
	let escapeMessage: Bool
	let referenceMessage: Message?
	let completionBlock: PrintedLineCompletion?
}

extension ServerSession {
	func printAndLog(_ chatLine: ChatLine, completionBlock: PrintedLineCompletion?) {
		presentation?.print(chatLine, completionBlock: completionBlock)
		writeToLogFile(chatLine)
	}

	/// The one way to print a line. Everything but the body, the author, the
	/// destination and the line's kind carries a default, so a caller states
	/// only what it actually decides.
	func print(
		_ messageBody: String,
		by nickname: String?,
		in conversation: Conversation?,
		as lineType: ChatLineKind,
		command: String?,
		receivedAt: Date = Date(),
		isEncrypted: Bool = false,
		escapeMessage: Bool = true,
		referenceMessage: Message? = nil,
		completionBlock: PrintedLineCompletion? = nil
	) {
		let request = LinePrintRequest(
			messageBody: messageBody,
			nickname: nickname,
			conversation: conversation,
			lineType: lineType,
			command: command,
			receivedAt: receivedAt,
			isEncrypted: isEncrypted,
			escapeMessage: escapeMessage,
			referenceMessage: referenceMessage,
			completionBlock: completionBlock
		)
		#if DEBUG
			if let linePrintObserver {
				linePrintObserver(request)
				return
			}
		#endif
		printOnMainActor(request)
	}
}

extension ServerSession {
	/// The last line printed to the console.
	var lastLine: ChatLine? {
		presentation?.lastPrintedLine()
	}

	func printReply(_ message: Message, in conversation: Conversation? = nil, withSequence sequence: UInt = 1) {
		print(message.sequence(sequence), by: nil, in: conversation, as: .debug, command: message.command,
		      receivedAt: message.receivedAt)
	}

	/// - Parameter sequence: The parameter the error text starts at; `nil` for
	/// the whole parameter list.
	func printErrorReply(_ message: Message, in conversation: Conversation? = nil, withSequence sequence: UInt? = nil) {
		let sequenceMessage = sequence.map { message.sequence($0) } ?? message.sequence
		let errorMessage = malformedMessageText(
			numeric: message.commandNumeric,
			sequence: sequenceMessage
		)
		print(errorMessage, by: nil, in: conversation, as: .debug, command: message.command)
	}

	func printError(_ errorMessage: String, asCommand command: String) {
		print(errorMessage, by: nil, in: nil, as: .debug, command: command)
	}

	func printDebugInformation(
		toConsole message: String,
		asCommand command: String = ChatLineFormat.defaultCommand,
		escapeMessage: Bool = true
	) {
		print(message, by: nil, in: nil, as: .debug, command: command, escapeMessage: escapeMessage)
	}

	/// Prints into whichever conversation of this session is selected, or the
	/// console when none is.
	func printDebugInformation(
		_ message: String,
		asCommand command: String = ChatLineFormat.defaultCommand,
		escapeMessage: Bool = true
	) {
		printDebugInformation(
			message,
			in: output?.selectedConversation(on: self),
			asCommand: command,
			escapeMessage: escapeMessage
		)
	}

	func printDebugInformation(multiline message: String) {
		message.enumerateLines { line, _ in
			self.printDebugInformation(line)
		}
	}

	func printDebugInformation(
		_ message: String,
		in conversation: Conversation?,
		asCommand command: String = ChatLineFormat.defaultCommand,
		escapeMessage: Bool = true
	) {
		print(message, by: nil, in: conversation, as: .debug, command: command, escapeMessage: escapeMessage)
	}
}

private extension ServerSession {
	@MainActor
	func printOnMainActor(_ request: LinePrintRequest) {
		precondition(request.command != nil || request.referenceMessage != nil)
		guard !isTerminating else { return }

		let command = request.command ?? request.referenceMessage?.command ?? ChatLineFormat.defaultCommand
		let conversation = request.conversation
		let memberType = LinePresentationPolicy.memberType(nickname: request.nickname, localNickname: userNickname)
		let keywordLists = highlightKeywordLists(
			for: conversation,
			lineType: request.lineType,
			memberType: memberType
		)
		let lineType = LinePresentationPolicy.normalized(request.lineType)
		var chatLine = ChatLine()
		chatLine.command = command.lowercased()
		chatLine.messageIdentifier = request.referenceMessage?.messageIdentifier
		chatLine.deliveryState = nextLineDeliveryState
		nextLineDeliveryState = .none

		let messageReplyIdentifier = request.referenceMessage?.messageTags?["+draft/reply"]
		let replyIdentifier = messageReplyIdentifier?.isEmpty == false
			? messageReplyIdentifier
			: nextLineReplyToMessageIdentifier
		nextLineReplyToMessageIdentifier = nil
		if let replyIdentifier, !replyIdentifier.isEmpty {
			chatLine.replyToMessageIdentifier = replyIdentifier
		}

		chatLine.lineType = lineType
		chatLine.memberType = memberType
		chatLine.isEncrypted = request.isEncrypted
		chatLine.excludeKeywords = keywordLists.exclude
		chatLine.highlightKeywords = keywordLists.match
		chatLine.nickname = request.nickname
		chatLine.messageBody = LinePresentationPolicy.messageBody(
			request.messageBody,
			memberType: memberType,
			removesIncomingFormatting: environment.settings.removeAllFormatting
		)
		let previousLine = conversation?.lastLine ?? lastLine
		chatLine.isFirstForDay = LinePresentationPolicy.isFirstForDay(
			receivedAt: request.receivedAt,
			previousDate: previousLine?.receivedAt
		)
		chatLine.receivedAt = request.receivedAt

		guard let conversation else {
			printAndLog(chatLine, completionBlock: request.completionBlock)
			return
		}
		if chatHistory.prependConversation === conversation {
			chatHistory.prependedLines?.append(chatLine)
			return
		}

		guard let output else {
			conversation.print(chatLine, completionBlock: request.completionBlock)
			return
		}
		if LinePresentationPolicy.needsUnreadMarker(
			autoMark: environment.settings.autoAddUnreadMarker,
			itemIsVisible: output.isItemVisible(conversation),
			windowIsMain: output.isMainWindow,
			conversationIsUnread: conversation.isUnread,
			lineType: lineType
		) {
			conversation.presentation?.mark()
		}
		let readGeneration = conversation.readStateGeneration
		let connectionIdentifier = socket?.uniqueIdentifier
		let isPlayback = lineIsJoinBurst(request.referenceMessage, in: conversation)
		conversation.print(chatLine) { [weak self, weak conversation] context in
			request.completionBlock?(context)
			guard let self, let conversation, !isTerminating,
			      socket?.uniqueIdentifier == connectionIdentifier,
			      conversation.associatedSession === self else { return }
			guard context.isDisplayed, !context.isDuplicate, !isPlayback, conversation.readStateGeneration == readGeneration,
			      self.output?.isKeyWindow == true, self.output?.isItemVisible(conversation) == true else { return }
			scheduleReadMarker(for: conversation, date: request.receivedAt)
		}
	}
}

/// What the console says about a numeric whose parameters it could not read.
private func malformedMessageText(numeric: UInt, sequence: String) -> String {
	// The numeric is server-controlled; an out-of-range one is reported
	// as 0 rather than trapping the conversion.
	String(localized: .IRC.miscellaneousMessagesRelatedMessage(Int32(exactly: numeric) ?? 0, sequence))
}
