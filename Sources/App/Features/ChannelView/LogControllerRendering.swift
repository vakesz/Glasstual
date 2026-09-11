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

/// Initial replay keeps raw archives distinct from the native rows it rendered.
nonisolated struct TranscriptHistoryRenderOutput: Sendable { // nonisolated: value
	let historicEntries: [LogLine]
	let entries: [LogLine]
	let results: [LogLineRenderResult]
	let fetchSucceeded: Bool
	let failure: HistoricLogFetchFailure?
}

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
	var inlineMediaEnabled = false
	var isChannel = false
	/// Whether a day boundary is drawn between lines. It is read from the
	/// preferences on the main actor and carried here, so rendering stays a
	/// function of the values it was handed.
	var showsDateChanges = false
	/// The preference facts the body renderer branches on, taken on the main
	/// actor for the same reason `showsDateChanges` is.
	var textPolicy = TranscriptTextPolicy()
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
	var lineType = LogLineType.undefined
	var memberType = LogLineMemberType.normal
	var nickname: String?
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var deliveryState = LogLineDeliveryState.none
	var reactions: [String: [String]]?
	var highlightKeywords: [String]?
	var excludeKeywords: [String]?
	var isEncrypted = false
	var isFirstForDay = false
	var fromCurrentSession = true
	var modeSymbol = ""
	var historyCursor: HistoricLogRowCursor?

	init() {}

	init(_ logLine: LogLine, in context: LogLineRenderContext, historyCursor: HistoricLogRowCursor? = nil) {
		self.historyCursor = historyCursor
		uniqueIdentifier = historyCursor?.rowURI ?? logLine.uniqueIdentifier
		messageBody = logLine.messageBody
		command = logLine.command
		receivedAt = logLine.receivedAt
		lineType = logLine.lineType
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
		fromCurrentSession = logLine.fromCurrentSession

		modeSymbol = if context.isChannel, let sender = logLine.nickname {
			context.member(named: sender)?.mark ?? ""
		} else {
			""
		}
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
	func makeObject(resolvingMembersIn channel: IRCChannel?) -> PluginPostedMessage {
		var pluginObject = PluginPostedMessage()
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
	/** Runs the plugins that rewrite a message before it is drawn.

	 Main-actor, and not because it touches the view: the plugin ABI declares
	 these callbacks on the main actor, and the manager they are reached through
	 keeps main-actor state beside its lock. It is the one part of rendering
	 that is not a function of its inputs, so it is taken before a render job
	 starts rather than inside one. */
	@MainActor
	static func applyingMessageRenderers(
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
		lines.map { render(LogLineRenderRequest(line: $0, context: context)) }
	}

	nonisolated static func renderJob(_ request: LogLineRenderRequest) -> LogLineRenderResult { // nonisolated: pure
		render(request)
	}

	private nonisolated static func render( // nonisolated: pure
		_ request: LogLineRenderRequest
	)
		-> LogLineRenderResult
	{
		let line = request.line
		let attributes = TranscriptRenderOptions(
			renderLinks: !LinkParser.bannedLineTypes.contains(LogLine.string(for: line.lineType) ?? ""),
			lineType: line.lineType,
			memberType: line.memberType,
			highlightKeywords: line.highlightKeywords ?? [],
			excludedKeywords: line.excludeKeywords ?? [],
			textPolicy: request.context.textPolicy
		)

		let body = LogRenderer.renderNativeBody(
			line.messageBody,
			withAttributes: attributes,
			members: request.context.members
		)
		let markers = markers(for: request)
		let transcriptLine = TranscriptLine(
			lineNumber: line.uniqueIdentifier,
			receivedAt: line.receivedAt,
			nickname: line.nickname,
			memberType: line.memberType,
			lineType: line.lineType,
			command: line.command,
			messageIdentifier: line.messageIdentifier,
			replyToMessageIdentifier: line.replyToMessageIdentifier,
			deliveryState: line.deliveryState,
			deliveryFailureReason: nil,
			reactions: request.context.reactions(for: line),
			markers: markers,
			body: body,
			modeSymbol: line.modeSymbol,
			historyCursor: line.historyCursor
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
		if request.line.isFirstForDay, request.context.showsDateChanges {
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
