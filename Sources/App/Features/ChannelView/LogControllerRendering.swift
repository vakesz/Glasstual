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
 *********************************************************************** */

import Foundation
import GlasstualPluginKit
import os

private nonisolated let logLineRenderingLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogLineRendering"
)

nonisolated struct RenderedMember: Sendable, Hashable { // nonisolated: value
	var nickname: String
	var mark: String

	init(nickname: String, mark: String = "") {
		self.nickname = nickname
		self.mark = mark
	}

	init(_ member: ChannelUser) {
		self.init(nickname: member.user.nickname, mark: member.mark)
	}
}

nonisolated struct LogLineRenderContext: Sendable { // nonisolated: value
	var networkName = ""
	var inlineMediaEnabled = false
	var isChannel = false
	var nicknameFormat = ""
	var members: [RenderedMember] = []
	var sessionReactions: [String: [String: [String]]] = [:]

	func member(named nickname: String) -> RenderedMember? {
		members.first { $0.nickname.caseInsensitiveCompare(nickname) == .orderedSame }
	}

	func reactions(for line: LogLineSnapshot) -> [String: [String]] {
		let archived = line.reactions ?? [:]
		guard let identifier = line.messageIdentifier,
		      let session = sessionReactions[identifier],
		      session.isEmpty == false
		else {
			return archived
		}
		var merged = archived
		for (emoji, nicknames) in session {
			var values = merged[emoji] ?? []
			for nickname in nicknames where values.contains(nickname) == false {
				values.append(nickname)
			}
			merged[emoji] = values
		}
		return merged
	}
}

nonisolated struct LogLineSnapshot: Sendable { // nonisolated: value
	var uniqueIdentifier = ""
	var messageBody = ""
	var command = ""
	var receivedAt = Date()
	var formattedTimestamp = ""
	var lineType = TVCLogLineType.undefined
	var lineTypeString: String?
	var memberType = TVCLogLineMemberType.normal
	var nickname: String?
	var formattedNickname = ""
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var deliveryState = TVCLogLineDeliveryState.none
	var reactions: [String: [String]]?
	var highlightKeywords: [String]?
	var excludeKeywords: [String]?
	var isEncrypted = false
	var isFirstForDay = false
	var sourceDescription = ""
	var fromCurrentSession = true

	init() {}

	init(_ logLine: LogLine, in context: LogLineRenderContext) {
		uniqueIdentifier = logLine.uniqueIdentifier
		messageBody = logLine.messageBody
		command = logLine.command
		receivedAt = logLine.receivedAt
		formattedTimestamp = logLine.formattedTimestamp
		lineType = logLine.lineType
		lineTypeString = logLine.lineTypeString
		memberType = logLine.memberType
		nickname = logLine.nickname
		messageIdentifier = logLine.messageIdentifier
		replyToMessageIdentifier = logLine.replyToMessageIdentifier
		deliveryState = logLine.deliveryState
		reactions = logLine.reactions
		highlightKeywords = logLine.highlightKeywords
		excludeKeywords = logLine.excludeKeywords
		isEncrypted = logLine.isEncrypted
		isFirstForDay = logLine.isFirstForDay
		sourceDescription = logLine.description
		fromCurrentSession = logLine.fromCurrentSession

		let modeSymbol = if context.isChannel, let sender = logLine.nickname {
			context.member(named: sender)?.mark ?? ""
		} else {
			""
		}
		formattedNickname = logLine
			.formattedNickname(modeSymbol: modeSymbol, format: context.nicknameFormat)?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
	}
}

nonisolated struct LogLineRenderRequest: Sendable { // nonisolated: value
	var line: LogLineSnapshot
	var context: LogLineRenderContext

	init(line: LogLineSnapshot, context: LogLineRenderContext) {
		self.line = line
		self.context = context
	}

	init(logLine: LogLine, context: LogLineRenderContext) {
		self.init(line: LogLineSnapshot(logLine, in: context), context: context)
	}
}

nonisolated struct RenderedPluginMessage: Sendable { // nonisolated: value
	var keywordMatchFound = false
	var lineTypeRawValue: UInt = 0
	var memberTypeRawValue: UInt = 0
	var senderNickname: String?
	var receivedAt = Date()
	var lineNumber = ""
	var messageContents = ""
	var hyperlinks: [LinkParserResult] = []
	var nicknames: [String] = []

	@MainActor
	func makeObject(resolvingMembersIn channel: IRCChannel?) -> THOPluginDidPostNewMessageConcreteObject {
		var pluginObject = THOPluginDidPostNewMessageConcreteObject()
		pluginObject.keywordMatchFound = keywordMatchFound
		pluginObject.lineTypeRawValue = lineTypeRawValue
		pluginObject.memberTypeRawValue = memberTypeRawValue
		pluginObject.senderNickname = senderNickname
		pluginObject.receivedAt = receivedAt
		pluginObject.lineNumber = lineNumber
		pluginObject.messageContents = messageContents
		pluginObject.hyperlinks = hyperlinks.map {
			PluginHyperlink(
				uniqueIdentifier: $0.uniqueIdentifier,
				stringValue: $0.stringValue,
				range: $0.range,
				strictMatch: $0.strictMatch
			)
		}
		pluginObject.users = nicknames
			.compactMap { channel?.findMember($0) }
			.map(PluginHostAdapter.makeMember)
		return pluginObject
	}
}

nonisolated struct LogLineRenderResult: Sendable { // nonisolated: value
	var transcriptLine: TranscriptLine
	var fromCurrentSession: Bool
	var processesInlineMedia: Bool
	var pluginMessage: RenderedPluginMessage?

	var lineNumber: String {
		transcriptLine.lineNumber
	}

	var timestamp: TimeInterval {
		transcriptLine.receivedAt.timeIntervalSince1970
	}

	var isHighlight: Bool {
		transcriptLine.body.isHighlight
	}

	var links: [LinkParserResult] {
		transcriptLine.body.links
	}

	var mentionedNicknames: [String] {
		transcriptLine.body.mentionedNicknames
	}
}

extension LogController {
	nonisolated static func applyingMessageRenderers( // nonisolated: pure
		to lines: [LogLineSnapshot],
		for viewController: LogController
	) -> [LogLineSnapshot] {
		lines.map { line in
			var line = line
			line.messageBody = PluginDispatcher.willRenderMessage(
				line.messageBody,
				forViewController: viewController,
				lineType: line.lineType,
				memberType: line.memberType
			)
			return line
		}
	}

	nonisolated static func renderJob( // nonisolated: pure
		_ lines: [LogLineSnapshot],
		context: LogLineRenderContext
	) -> [LogLineRenderResult] {
		lines.compactMap { render(LogLineRenderRequest(line: $0, context: context)) }
	}

	nonisolated static func renderJob(_ request: LogLineRenderRequest) -> LogLineRenderResult? { // nonisolated: pure
		render(request)
	}

	private nonisolated static func render( // nonisolated: pure
		_ request: LogLineRenderRequest
	)
		-> LogLineRenderResult?
	{
		let line = request.line
		let lineTypeString = line.lineTypeString ?? ""
		var attributes = LogRendererConfiguration()
		if let excluded = line.excludeKeywords {
			attributes[.excludedKeywords] = excluded
		}
		if let highlighted = line.highlightKeywords {
			attributes[.highlightKeywords] = highlighted
		}
		attributes[.renderLinks] = LinkParser.bannedLineTypes.contains(lineTypeString) == false
		attributes[.lineType] = line.lineType.rawValue
		attributes[.memberType] = line.memberType.rawValue

		let body = LogRenderer.renderNativeBody(
			line.messageBody,
			withAttributes: attributes,
			members: request.context.members
		)
		let markers = markers(for: request)
		let transcriptLine = TranscriptLine(
			lineNumber: line.uniqueIdentifier,
			receivedAt: line.receivedAt,
			timestamp: line.formattedTimestamp,
			nickname: line.nickname,
			formattedNickname: line.formattedNickname,
			memberType: line.memberType,
			lineType: line.lineType,
			command: line.command,
			messageIdentifier: line.messageIdentifier,
			replyToMessageIdentifier: line.replyToMessageIdentifier,
			deliveryState: line.deliveryState,
			deliveryFailureReason: nil,
			reactions: request.context.reactions(for: line),
			markers: markers,
			body: body
		)
		let inlineMedia = request.context.inlineMediaEnabled &&
			(line.lineType == .privateMessage || line.lineType == .action)
		return LogLineRenderResult(
			transcriptLine: transcriptLine,
			fromCurrentSession: line.fromCurrentSession,
			processesInlineMedia: inlineMedia,
			pluginMessage: makePluginMessage(for: line, body: body)
		)
	}

	private nonisolated static func markers( // nonisolated: pure
		for request: LogLineRenderRequest
	)
		-> [TranscriptMarker]
	{
		var result: [TranscriptMarker] = []
		if request.line.isFirstForDay, Preferences.Messages.showDateChanges.detachedValue {
			result.append(.date(formatDate(request.line.receivedAt, .long, .none, false) ?? ""))
		}
		return result
	}

	private nonisolated static func makePluginMessage( // nonisolated: pure
		for line: LogLineSnapshot,
		body: TranscriptBody
	) -> RenderedPluginMessage? {
		guard SharedApplication.sharedPluginManager().supportsFeature(.newMessagePostedEvent) else {
			return nil
		}
		return RenderedPluginMessage(
			keywordMatchFound: body.isHighlight,
			lineTypeRawValue: line.lineType.rawValue,
			memberTypeRawValue: line.memberType.rawValue,
			senderNickname: line.nickname,
			receivedAt: line.receivedAt,
			lineNumber: line.uniqueIdentifier,
			messageContents: body.plainText,
			hyperlinks: body.links,
			nicknames: body.mentionedNicknames
		)
	}
}
