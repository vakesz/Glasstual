/* *********************************************************************
  *                  _____         _               _
  *                 |_   _|____  _| |_ _   _  __ _| |
  *                   | |/ _ \\ \/ / __| | | |/ _` | |
  *                   | |  __/>  <| |_| |_| | (_| | |
  *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
  *
  * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
  * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
  *       Please see Acknowledgements.pdf for additional information.
 + *
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

enum IRCLinePresentationPolicy {
	static func memberType(nickname: String?, localNickname: String) -> TVCLogLineMemberType {
		nickname == localNickname ? .localUser : .normal
	}

	static func normalized(_ lineType: TVCLogLineType) -> TVCLogLineType {
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
		lineType: TVCLogLineType,
		memberType: TVCLogLineMemberType
	) -> Bool {
		channelExists && ignoresHighlights == false &&
			(lineType == .privateMessage || lineType == .action) && memberType == .normal
	}

	static func needsScrollbackMark(
		autoMark: Bool,
		itemIsVisible: Bool,
		windowIsMain: Bool,
		channelIsUnread: Bool,
		lineType: TVCLogLineType
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

struct IRCLinePrintRequest {
	let messageBody: String
	let nickname: String?
	let channel: IRCChannel?
	let lineType: TVCLogLineType
	let command: String?
	let receivedAt: Date
	let isEncrypted: Bool
	let escapeMessage: Bool
	let referenceMessage: Message?
	let completionBlock: LogControllerPrintOperationCompletion?
}

public extension IRCClient {
	@objc(formatNickname:inChannel:)
	func formatNickname(_ nickname: String, in channel: IRCChannel?) -> String {
		formatNickname(nickname, in: channel, withFormat: nil)
	}

	@objc(formatNickname:inChannel:withFormat:)
	func formatNickname(_ nickname: String, in channel: IRCChannel?, withFormat format: String?) -> String {
		formatNicknameOnMainActor(nickname, in: channel, format: format)
	}

	@objc(printAndLog:completionBlock:)
	func printAndLog(_ logLine: LogLine, completionBlock: LogControllerPrintOperationCompletion?) {
		presentation?.print(logLine, completionBlock: completionBlock)
		writeToLogFile(logLine)
	}

	@objc(print:by:inChannel:asType:command:)
	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: IRCChannel?,
		as lineType: TVCLogLineType,
		command: String
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: Date(),
		      isEncrypted: false, escapeMessage: true, referenceMessage: nil, completionBlock: nil)
	}

	@objc(print:by:inChannel:asType:command:escapeMessage:)
	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: IRCChannel?,
		as lineType: TVCLogLineType,
		command: String,
		escapeMessage: Bool
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: Date(),
		      isEncrypted: false, escapeMessage: escapeMessage, referenceMessage: nil, completionBlock: nil)
	}

	@objc(print:by:inChannel:asType:command:receivedAt:)
	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: IRCChannel?,
		as lineType: TVCLogLineType,
		command: String,
		receivedAt: Date
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: receivedAt,
		      isEncrypted: false, escapeMessage: true, referenceMessage: nil, completionBlock: nil)
	}

	@objc(print:by:inChannel:asType:command:receivedAt:isEncrypted:)
	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: IRCChannel?,
		as lineType: TVCLogLineType,
		command: String,
		receivedAt: Date,
		isEncrypted: Bool
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: receivedAt,
		      isEncrypted: isEncrypted, escapeMessage: true, referenceMessage: nil, completionBlock: nil)
	}

	@objc(print:by:inChannel:asType:command:receivedAt:isEncrypted:referenceMessage:)
	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: IRCChannel?,
		as lineType: TVCLogLineType,
		command: String?,
		receivedAt: Date,
		isEncrypted: Bool,
		referenceMessage: Message? = nil
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: receivedAt,
		      isEncrypted: isEncrypted, escapeMessage: true, referenceMessage: referenceMessage,
		      completionBlock: nil)
	}

	@objc(print:by:inChannel:asType:command:receivedAt:isEncrypted:referenceMessage:completionBlock:)
	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: IRCChannel?,
		as lineType: TVCLogLineType,
		command: String?,
		receivedAt: Date,
		isEncrypted: Bool,
		referenceMessage: Message? = nil,
		completionBlock: LogControllerPrintOperationCompletion? = nil
	) {
		print(messageBody, by: nickname, in: channel, as: lineType, command: command, receivedAt: receivedAt,
		      isEncrypted: isEncrypted, escapeMessage: true, referenceMessage: referenceMessage,
		      completionBlock: completionBlock)
	}

	@objc(print:by:inChannel:asType:command:receivedAt:isEncrypted:escapeMessage:referenceMessage:completionBlock:)
	func print(
		_ messageBody: String,
		by nickname: String?,
		in channel: IRCChannel?,
		as lineType: TVCLogLineType,
		command: String?,
		receivedAt: Date,
		isEncrypted: Bool,
		escapeMessage: Bool = true,
		referenceMessage: Message? = nil,
		completionBlock: LogControllerPrintOperationCompletion? = nil
	) {
		let request = IRCLinePrintRequest(
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

public extension IRCClient {
	@objc(printReply:)
	func printReply(_ message: Message) {
		printReply(message, in: nil)
	}

	@objc(printReply:inChannel:)
	func printReply(_ message: Message, in channel: IRCChannel?) {
		printReply(message, in: channel, withSequence: 1)
	}

	@objc(printReply:inChannel:withSequence:)
	func printReply(_ message: Message, in channel: IRCChannel?, withSequence sequence: UInt) {
		print(message.sequence(sequence), by: nil, in: channel, as: .debug, command: message.command,
		      receivedAt: message.receivedAt)
	}

	@objc(printErrorReply:)
	func printErrorReply(_ message: Message) {
		printErrorReply(message, in: nil)
	}

	@objc(printErrorReply:inChannel:)
	func printErrorReply(_ message: Message, in channel: IRCChannel?) {
		printErrorReply(message, in: channel, withSequence: UInt(NSNotFound))
	}

	@objc(printErrorReply:inChannel:withSequence:)
	func printErrorReply(_ message: Message, in channel: IRCChannel?, withSequence sequence: UInt) {
		let sequenceMessage = sequence == UInt(NSNotFound) ? message.sequence : message.sequence(sequence)
		let errorMessage = IRCDiagnosticStrings.malformedMessage(
			numeric: message.commandNumeric,
			sequence: sequenceMessage
		)
		print(errorMessage, by: nil, in: channel, as: .debug, command: message.command)
	}

	@objc(printError:asCommand:)
	func printError(_ errorMessage: String, asCommand command: String) {
		print(errorMessage, by: nil, in: nil, as: .debug, command: command)
	}

	@objc(printDebugInformationToConsole:)
	func printDebugInformation(toConsole message: String) {
		printDebugInformation(toConsole: message, asCommand: TVCLogLineDefaultCommandValue, escapeMessage: true)
	}

	@objc(printDebugInformationToConsole:asCommand:)
	func printDebugInformation(toConsole message: String, asCommand command: String) {
		printDebugInformation(toConsole: message, asCommand: command, escapeMessage: true)
	}

	@objc(printDebugInformationToConsole:escapeMessage:)
	func printDebugInformation(toConsole message: String, escapeMessage: Bool) {
		printDebugInformation(
			toConsole: message,
			asCommand: TVCLogLineDefaultCommandValue,
			escapeMessage: escapeMessage
		)
	}

	@objc(printDebugInformationToConsole:asCommand:escapeMessage:)
	func printDebugInformation(toConsole message: String, asCommand command: String, escapeMessage: Bool) {
		print(message, by: nil, in: nil, as: .debug, command: command, escapeMessage: escapeMessage)
	}

	@objc(printDebugInformation:)
	func printDebugInformation(_ message: String) {
		printDebugInformation(message, asCommand: TVCLogLineDefaultCommandValue, escapeMessage: true)
	}

	@objc(printDebugInformationMultiline:)
	func printDebugInformation(multiline message: String) {
		message.enumerateLines { line, _ in
			self.printDebugInformation(line)
		}
	}

	@objc(printDebugInformation:asCommand:)
	func printDebugInformation(_ message: String, asCommand command: String) {
		printDebugInformation(message, asCommand: command, escapeMessage: true)
	}

	@objc(printDebugInformation:escapeMessage:)
	func printDebugInformation(_ message: String, escapeMessage: Bool) {
		printDebugInformation(message, asCommand: TVCLogLineDefaultCommandValue, escapeMessage: escapeMessage)
	}

	@objc(printDebugInformation:asCommand:escapeMessage:)
	func printDebugInformation(_ message: String, asCommand command: String, escapeMessage: Bool) {
		let channel = output?.selectedChannel(on: self)

		printDebugInformation(
			message,
			in: channel,
			asCommand: command,
			escapeMessage: escapeMessage
		)
	}

	@objc(printDebugInformation:inChannel:)
	func printDebugInformation(_ message: String, in channel: IRCChannel?) {
		printDebugInformation(message, in: channel, asCommand: TVCLogLineDefaultCommandValue, escapeMessage: true)
	}

	@objc(printDebugInformation:inChannel:asCommand:)
	func printDebugInformation(_ message: String, in channel: IRCChannel?, asCommand command: String) {
		print(message, by: nil, in: channel, as: .debug, command: command, escapeMessage: true)
	}

	@objc(printDebugInformation:inChannel:escapeMessage:)
	func printDebugInformation(_ message: String, in channel: IRCChannel?, escapeMessage: Bool) {
		printDebugInformation(
			message,
			in: channel,
			asCommand: TVCLogLineDefaultCommandValue,
			escapeMessage: escapeMessage
		)
	}

	@objc(printDebugInformation:inChannel:asCommand:escapeMessage:)
	func printDebugInformation(
		_ message: String,
		in channel: IRCChannel?,
		asCommand command: String,
		escapeMessage: Bool
	) {
		print(message, by: nil, in: channel, as: .debug, command: command, escapeMessage: escapeMessage)
	}

	@objc(printDebugInformationInAllViews:)
	func printDebugInformation(inAllViews message: String) {
		printDebugInformation(
			inAllViews: message,
			asCommand: TVCLogLineDefaultCommandValue,
			escapeMessage: true
		)
	}

	@objc(printDebugInformationInAllViews:asCommand:)
	func printDebugInformation(inAllViews message: String, asCommand command: String) {
		printDebugInformation(inAllViews: message, asCommand: command, escapeMessage: true)
	}

	@objc(printDebugInformationInAllViews:escapeMessage:)
	func printDebugInformation(inAllViews message: String, escapeMessage: Bool) {
		printDebugInformation(
			inAllViews: message,
			asCommand: TVCLogLineDefaultCommandValue,
			escapeMessage: escapeMessage
		)
	}

	@objc(printDebugInformationInAllViews:asCommand:escapeMessage:)
	func printDebugInformation(inAllViews message: String, asCommand command: String, escapeMessage: Bool) {
		for channel in channelList {
			printDebugInformation(message, in: channel, asCommand: command, escapeMessage: escapeMessage)
		}
		printDebugInformation(toConsole: message, asCommand: command, escapeMessage: escapeMessage)
	}
}

private extension IRCClient {
	@MainActor
	func formatNicknameOnMainActor(_ nickname: String, in channel: IRCChannel?, format: String?) -> String {
		let requestedFormat = format?.isEmpty == false ? format : nil
		let themeFormat = SharedApplication.sharedThemeController().settings.themeNicknameFormat
		let resolvedFormat = requestedFormat ?? themeFormat ?? environment.preferences.themeNicknameFormat
		let finalFormat = resolvedFormat.isEmpty ? environment.preferences.themeNicknameFormatDefault : resolvedFormat
		let modeSymbol: String = if channel?.isChannel == true, let member = channel?.findMember(nickname) {
			member.mark
		} else {
			""
		}
		return ClientWireUtilities.formatNickname(nickname, modeSymbol: modeSymbol, format: finalFormat)
	}

	@MainActor
	func printOnMainActor(_ request: IRCLinePrintRequest) {
		precondition(request.command != nil || request.referenceMessage != nil)
		guard !isTerminating else { return }

		let command = request.command ?? request.referenceMessage?.command ?? TVCLogLineDefaultCommandValue
		let channel = request.channel
		guard channel == nil || !outputRuleMatched(in: request.messageBody, channel: channel) else { return }

		let memberType = IRCLinePresentationPolicy.memberType(nickname: request.nickname, localNickname: userNickname)
		let keywordLists = highlightKeywordLists(
			for: channel,
			lineType: request.lineType,
			memberType: memberType
		)
		let lineType = IRCLinePresentationPolicy.normalized(request.lineType)
		let logLine = LogLine()
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
		logLine.rendererAttributes = request.escapeMessage ? nil : [.doNotEscapeBodyAttribute: true]
		logLine.nickname = request.nickname
		logLine.messageBody = request.messageBody
		let previousLine = channel?.lastLine ?? lastLine
		logLine.isFirstForDay = IRCLinePresentationPolicy.isFirstForDay(
			receivedAt: request.receivedAt,
			previousDate: previousLine?.receivedAt
		)
		logLine.receivedAt = request.receivedAt

		guard let channel else {
			printAndLog(logLine, completionBlock: request.completionBlock)
			return
		}
		if chatHistoryPrependChannel === channel {
			chatHistoryPrependedLines?.append(logLine.duplicate())
			return
		}

		guard let output else {
			channel.print(logLine, completionBlock: request.completionBlock)
			return
		}
		if IRCLinePresentationPolicy.needsScrollbackMark(
			autoMark: environment.preferences.autoAddScrollbackMark,
			itemIsVisible: output.isItemVisible(legacyTreeItem(channel)),
			windowIsMain: output.windowIsMain,
			channelIsUnread: channel.isUnread,
			lineType: lineType
		) {
			channel.presentation?.mark()
		}
		channel.print(logLine, completionBlock: request.completionBlock)
		if output.windowIsKey, output.isItemVisible(legacyTreeItem(channel)) {
			scheduleReadMarker(for: channel, date: request.receivedAt)
		}
	}

	@MainActor
	func highlightKeywordLists(
		for channel: IRCChannel?,
		lineType: TVCLogLineType,
		memberType: TVCLogLineMemberType
	) -> (exclude: [String]?, match: [String]?) {
		guard IRCLinePresentationPolicy.allowsHighlightMatching(
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

	func legacyTreeItem(_ channel: IRCChannel) -> IRCTreeItem {
		channel
	}
}
