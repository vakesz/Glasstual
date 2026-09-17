// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum LinePresentationPolicy {
	static func memberType(nickname: String?, localNickname: String) -> LogLineMemberType {
		nickname == localNickname ? .localUser : .normal
	}

	/// The body a printed line keeps. "Remove formatting from incoming
	/// messages" strips the control codes of everything but the local user's
	/// own lines, and only the text: the line was parsed as it arrived.
	static func messageBody(
		_ body: String,
		memberType: LogLineMemberType,
		removesIncomingFormatting: Bool
	) -> String {
		guard removesIncomingFormatting, memberType != .localUser else { return body }
		return (body as NSString).stripIRCEffects
	}

	static func normalized(_ lineType: LogLineType) -> LogLineType {
		switch lineType {
		case .actionNoHighlight:
			.action
		case .privateMessageNoHighlight:
			.privateMessage
		default:
			lineType
		}
	}

	static func allowsHighlightMatching(
		channelExists: Bool,
		ignoresHighlights: Bool,
		lineType: LogLineType,
		memberType: LogLineMemberType
	) -> Bool {
		channelExists && ignoresHighlights == false &&
			(lineType == .privateMessage || lineType == .action) && memberType == .normal
	}

	static func needsScrollbackMark(
		autoMark: Bool,
		itemIsVisible: Bool,
		windowIsMain: Bool,
		channelIsUnread: Bool,
		lineType: LogLineType
	) -> Bool {
		guard autoMark, itemIsVisible == false || windowIsMain == false, channelIsUnread == false else {
			return false
		}
		return lineType == .privateMessage || lineType == .action || lineType == .notice
	}

	static func isFirstForDay(receivedAt: Date, previousDate: Date?) -> Bool {
		guard let previousDate else { return true }
		return Calendar.current.isDate(receivedAt, inSameDayAs: previousDate) == false
	}
}

struct LinePrintRequest {
	let messageBody: String
	let nickname: String?
	let channel: Channel?
	let lineType: LogLineType
	let command: String?
	let receivedAt: Date
	let isEncrypted: Bool
	let escapeMessage: Bool
	let referenceMessage: Message?
	let completionBlock: PrintedLineCompletion?
}

extension Client {
	func formatNickname(_ nickname: String, in channel: Channel?, withFormat format: String? = nil) -> String {
		let requestedFormat = format?.isEmpty == false ? format : nil
		let themeFormat = AppServices.theme.theme.nicknameFormat
		let resolvedFormat = requestedFormat ?? themeFormat
		let finalFormat = resolvedFormat.isEmpty ? TranscriptTheme.lines.nicknameFormat : resolvedFormat
		let modeSymbol: String = if channel?.isChannel == true, let member = channel?.findMember(nickname) {
			member.mark
		} else {
			""
		}
		return formattedNickname(nickname, modeSymbol: modeSymbol, format: finalFormat)
	}

	func printAndLog(_ logLine: LogLine, completionBlock: PrintedLineCompletion?) {
		presentation?.print(logLine, completionBlock: completionBlock)
		writeToLogFile(logLine)
	}

	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: Channel?,
		as lineType: LogLineType,
		command: String
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: Date(),
		      isEncrypted: false, escapeMessage: true, referenceMessage: nil, completionBlock: nil)
	}

	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: Channel?,
		as lineType: LogLineType,
		command: String,
		escapeMessage: Bool
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: Date(),
		      isEncrypted: false, escapeMessage: escapeMessage, referenceMessage: nil, completionBlock: nil)
	}

	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: Channel?,
		as lineType: LogLineType,
		command: String,
		receivedAt: Date
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: receivedAt,
		      isEncrypted: false, escapeMessage: true, referenceMessage: nil, completionBlock: nil)
	}

	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: Channel?,
		as lineType: LogLineType,
		command: String?,
		receivedAt: Date,
		isEncrypted: Bool,
		escapeMessage: Bool = true,
		referenceMessage: Message? = nil,
		completionBlock: PrintedLineCompletion? = nil
	) {
		let request = LinePrintRequest(
			messageBody: messageBody,
			nickname: nickname,
			channel: channel,
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

extension Client {
	/// The last line printed to the console.
	var lastLine: LogLine? {
		presentation?.lastPrintedLine()
	}

	func printReply(_ message: Message, in channel: Channel? = nil, withSequence sequence: UInt = 1) {
		print(message.sequence(sequence), by: nil, in: channel, as: .debug, command: message.command,
		      receivedAt: message.receivedAt)
	}

	/// - Parameter sequence: The parameter the error text starts at; `nil` for
	/// the whole parameter list.
	func printErrorReply(_ message: Message, in channel: Channel? = nil, withSequence sequence: UInt? = nil) {
		let sequenceMessage = sequence.map { message.sequence($0) } ?? message.sequence
		let errorMessage = malformedMessageText(
			numeric: message.commandNumeric,
			sequence: sequenceMessage
		)
		print(errorMessage, by: nil, in: channel, as: .debug, command: message.command)
	}

	func printError(_ errorMessage: String, asCommand command: String) {
		print(errorMessage, by: nil, in: nil, as: .debug, command: command)
	}

	func printDebugInformation(
		toConsole message: String,
		asCommand command: String = LogLineFormat.defaultCommand,
		escapeMessage: Bool = true
	) {
		print(message, by: nil, in: nil, as: .debug, command: command, escapeMessage: escapeMessage)
	}

	/// Prints into whichever channel of this client is selected, or the console
	/// when none is.
	func printDebugInformation(
		_ message: String,
		asCommand command: String = LogLineFormat.defaultCommand,
		escapeMessage: Bool = true
	) {
		printDebugInformation(
			message,
			in: output?.selectedChannel(on: self),
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
		in channel: Channel?,
		asCommand command: String = LogLineFormat.defaultCommand,
		escapeMessage: Bool = true
	) {
		print(message, by: nil, in: channel, as: .debug, command: command, escapeMessage: escapeMessage)
	}

	func printDebugInformation(
		inAllViews message: String,
		asCommand command: String = LogLineFormat.defaultCommand,
		escapeMessage: Bool = true
	) {
		for channel in channelList {
			printDebugInformation(message, in: channel, asCommand: command, escapeMessage: escapeMessage)
		}
		printDebugInformation(toConsole: message, asCommand: command, escapeMessage: escapeMessage)
	}
}

private extension Client {
	@MainActor
	func printOnMainActor(_ request: LinePrintRequest) {
		precondition(request.command != nil || request.referenceMessage != nil)
		guard !isTerminating else { return }

		let command = request.command ?? request.referenceMessage?.command ?? LogLineFormat.defaultCommand
		let channel = request.channel
		let memberType = LinePresentationPolicy.memberType(nickname: request.nickname, localNickname: userNickname)
		let keywordLists = highlightKeywordLists(
			for: channel,
			lineType: request.lineType,
			memberType: memberType
		)
		let lineType = LinePresentationPolicy.normalized(request.lineType)
		var logLine = LogLine()
		logLine.command = command.lowercased()
		logLine.messageIdentifier = request.referenceMessage?.messageIdentifier
		logLine.deliveryState = nextLineDeliveryState
		nextLineDeliveryState = .none

		let messageReplyIdentifier = request.referenceMessage?.messageTags?["+draft/reply"]
		let replyIdentifier = messageReplyIdentifier?.isEmpty == false
			? messageReplyIdentifier
			: nextLineReplyToMessageIdentifier
		nextLineReplyToMessageIdentifier = nil
		if let replyIdentifier, !replyIdentifier.isEmpty {
			logLine.replyToMessageIdentifier = replyIdentifier
		}

		logLine.lineType = lineType
		logLine.memberType = memberType
		logLine.isEncrypted = request.isEncrypted
		logLine.excludeKeywords = keywordLists.exclude
		logLine.highlightKeywords = keywordLists.match
		logLine.nickname = request.nickname
		logLine.messageBody = LinePresentationPolicy.messageBody(
			request.messageBody,
			memberType: memberType,
			removesIncomingFormatting: environment.preferences.removeAllFormatting
		)
		let previousLine = channel?.lastLine ?? lastLine
		logLine.isFirstForDay = LinePresentationPolicy.isFirstForDay(
			receivedAt: request.receivedAt,
			previousDate: previousLine?.receivedAt
		)
		logLine.receivedAt = request.receivedAt

		guard let channel else {
			printAndLog(logLine, completionBlock: request.completionBlock)
			return
		}
		if chatHistory.prependChannel === channel {
			chatHistory.prependedLines?.append(logLine)
			return
		}

		guard let output else {
			channel.print(logLine, completionBlock: request.completionBlock)
			return
		}
		if LinePresentationPolicy.needsScrollbackMark(
			autoMark: environment.preferences.autoAddScrollbackMark,
			itemIsVisible: output.isItemVisible(channel),
			windowIsMain: output.isMainWindow,
			channelIsUnread: channel.isUnread,
			lineType: lineType
		) {
			channel.presentation?.mark()
		}
		let readGeneration = channel.readStateGeneration
		let connectionIdentifier = socket?.uniqueIdentifier
		let isPlayback = lineIsJoinBurst(request.referenceMessage, in: channel)
		channel.print(logLine) { [weak self, weak channel] context in
			request.completionBlock?(context)
			guard let self, let channel, !isTerminating,
			      socket?.uniqueIdentifier == connectionIdentifier,
			      channel.associatedClient === self else { return }
			guard context.isDisplayed, !context.isDuplicate, !isPlayback, channel.readStateGeneration == readGeneration,
			      self.output?.isKeyWindow == true, self.output?.isItemVisible(channel) == true else { return }
			scheduleReadMarker(for: channel, date: request.receivedAt)
		}
	}

	@MainActor
	func highlightKeywordLists(
		for channel: Channel?,
		lineType: LogLineType,
		memberType: LogLineMemberType
	) -> (exclude: [String]?, match: [String]?) {
		guard LinePresentationPolicy.allowsHighlightMatching(
			channelExists: channel != nil,
			ignoresHighlights: channel?.config.ignoreHighlights ?? false,
			lineType: lineType,
			memberType: memberType
		), let channel else {
			return (nil, nil)
		}

		var excluded = environment.preferences.highlightExcludeKeywords
		var matches = environment.preferences.highlightMatchKeywords
		if environment.preferences.highlightMatchingMethod != .regularExpression,
		   environment.preferences.highlightCurrentNickname
		{
			appendIfMissing(userNickname, to: &matches)
		}
		for condition in config.highlightList {
			if let channelIdentifier = condition.matchChannelId,
			   !channelIdentifier.isEmpty,
			   channelIdentifier != channel.uniqueIdentifier
			{
				continue
			}
			if condition.matchIsExcluded {
				appendIfMissing(condition.matchKeyword, to: &excluded)
			} else {
				appendIfMissing(condition.matchKeyword, to: &matches)
			}
		}
		return (excluded, matches)
	}

	func appendIfMissing(_ value: String, to values: inout [String]) {
		if !values.contains(value) {
			values.append(value)
		}
	}
}

extension Client {
	/** How many highlights one client keeps.

	 The cache exists so the highlight sheet can be opened after the fact; it
	 draws a finite list, and nothing else reads more than the newest entry.
	 Without a ceiling a long session on a highlight-heavy channel holds every
	 `LogLine` it ever matched for the life of the process. */
	static let maximumCachedHighlights = 500
}

/// What the console says about a numeric whose parameters it could not read.
private func malformedMessageText(numeric: UInt, sequence: String) -> String {
	// The numeric is server-controlled; an out-of-range one is reported
	// as 0 rather than trapping the conversion.
	String(localized: .IRC.miscellaneousMessagesRelatedMessage(Int32(exactly: numeric) ?? 0, sequence))
}

/** A nickname written the way the theme's nickname format asks for.

 `%n` is the name, `%@` the sender's mode symbol in the channel and `%%` a
 literal per cent; a number before any of them pads to that width, negative on
 the left. The format is the user's, so the padding width is clamped rather
 than trusted. */
func formattedNickname(_ nickname: String, modeSymbol: String, format: String) -> String {
	let scanner = Scanner(string: format)
	scanner.charactersToBeSkipped = nil

	var output = ""

	while scanner.isAtEnd == false {
		if let literal = scanner.scanUpToString("%") {
			output += literal
		}

		guard scanner.scanString("%") != nil else {
			break
		}

		let paddingWidth = scanner.scanInt() ?? 0
		let substitution: String? = if scanner.scanString("@") != nil {
			modeSymbol
		} else if scanner.scanString("n") != nil {
			nickname
		} else if scanner.scanString("%") != nil {
			"%"
		} else {
			nil
		}

		guard let substitution else {
			continue
		}

		let substitutionLength = (substitution as NSString).length
		// `abs(Int.min)` traps, and no sane format asks for more padding
		// than a line can hold, so the magnitude is clamped instead.
		let requestedWidth = Int(min(paddingWidth.magnitude, UInt(maximumNicknameFormatPaddingWidth)))
		let padding = String(repeating: " ", count: max(0, requestedWidth - substitutionLength))

		if paddingWidth < 0 {
			output += padding
		}

		output += substitution

		if paddingWidth > 0 {
			output += padding
		}
	}

	return output
}

/// Ceiling on `%<width>n` style padding in the nickname format. The width comes
/// from a user preference, so it needs a bound rather than trust.
private let maximumNicknameFormatPaddingWidth = 256

@MainActor
extension Client {
	func clearCachedHighlights() {
		cachedHighlights = []
	}

	func cacheHighlight(in channel: Channel, with logLine: LogLine) {
		guard environment.preferences.logHighlights else { return }

		let newEntry = HighlightLogEntry(
			lineLogged: logLine,
			clientId: uniqueIdentifier,
			channelId: channel.uniqueIdentifier
		)
		/* Appended rather than inserted at the front: inserting copied the whole
		 array on every highlight, and the one reader sorts by time anyway. */
		cachedHighlights.append(newEntry)

		if cachedHighlights.count > Self.maximumCachedHighlights {
			cachedHighlights.removeFirst(cachedHighlights.count - Self.maximumCachedHighlights)
		}

		output?.highlightWasLogged(newEntry)
	}
}
