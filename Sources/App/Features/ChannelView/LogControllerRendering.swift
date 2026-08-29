/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

import AppKit
import CocoaExtensions
import Foundation
import GlasstualPluginKit
import os

private nonisolated let logLineRenderingLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogLineRendering"
)

/** One channel member as rendering sees it: the nickname it matches on and the
 mode symbol it draws in front of it.

 A value, not the `ChannelUser` itself. The member list replaces and re-sorts
 its members while a line renders, and the render pipeline runs off the main
 actor, so what crosses is a copy taken at submission time. */
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

/// The main-actor state that every line rendered by one pipeline job needs.
/// Captured before the job is submitted so that rendering never reaches back
/// into the controller for it.
nonisolated struct LogLineRenderContext: Sendable { // nonisolated: value
	var networkName = ""
	var styleAbsolutePath = ""
	var inlineMediaEnabled = false
	/// Whether the view belongs to a channel rather than a query or a console.
	var isChannel = false
	/// The nickname format the theme and the preferences resolve to.
	var nicknameFormat = ""
	/** The channel's members as of when the job was submitted. Rendering marks
	 up nicknames from these instead of reaching back into the live channel. */
	var members: [RenderedMember] = []
	/// Line number that carries the "current session" marker, if any.
	var sessionIndicatorLineNumber: String?
	/// Reactions received during this session, keyed by message identifier.
	var sessionReactions: [String: [String: [String]]] = [:]

	/// The member of `members` named `nickname`, compared the way IRC compares them.
	func member(named nickname: String) -> RenderedMember? {
		members.first { $0.nickname.caseInsensitiveCompare(nickname) == .orderedSame }
	}

	/// Merges the reactions archived with the line and those seen this session.
	func reactions(for line: LogLineSnapshot) -> [String: [String]]? {
		let archived = line.reactions
		let session = line.messageIdentifier.flatMap { sessionReactions[$0] }
		guard let session, session.isEmpty == false else {
			return archived
		}
		guard let archived, archived.isEmpty == false else {
			return session
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

/** A log line reduced to the values rendering reads.

 `LogLine` is a mutable reference type carrying an untyped `rendererAttributes`
 dictionary, so it cannot cross into the pipeline. The snapshot is taken on the
 main actor, which is also where the sender's formatted nickname is resolved:
 that needs the member's mode symbol, and the member list is main-actor state. */
nonisolated struct LogLineSnapshot: Sendable { // nonisolated: value
	var uniqueIdentifier = ""
	var messageBody = ""
	var command = ""
	var receivedAt = Date()
	var formattedTimestamp = ""
	var lineType = TVCLogLineType.undefined
	var lineTypeString: String?
	var memberType = TVCLogLineMemberType.normal
	var memberTypeString = ""
	var nickname: String?
	/// The sender as the theme's nickname format renders it, empty when there
	/// is no sender to draw.
	var formattedNickname = ""
	var nicknameColorStyle = ""
	var nicknameColorStyleOverride = false
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var deliveryStateString: String?
	var reactions: [String: [String]]?
	var highlightKeywords: [String]?
	var excludeKeywords: [String]?
	/** The only key the app ever writes into `LogLine.rendererAttributes`
	 (`IRCClientLinePresentation`), and the only one an archived line can carry
	 that the render path does not overwrite from the line itself. */
	var doNotEscapeBody = false
	var isEncrypted = false
	var isFirstForDay = false
	/// What the failure log prints when a line will not render.
	var sourceDescription = ""

	init() {}

	/// Takes the snapshot. `context` supplies the mode symbol and the nickname
	/// format, so the sender is formatted here rather than off the main actor.
	init(_ logLine: LogLine, in context: LogLineRenderContext) {
		uniqueIdentifier = logLine.uniqueIdentifier
		messageBody = logLine.messageBody
		command = logLine.command
		receivedAt = logLine.receivedAt
		formattedTimestamp = logLine.formattedTimestamp
		lineType = logLine.lineType
		lineTypeString = logLine.lineTypeString
		memberType = logLine.memberType
		memberTypeString = logLine.memberTypeString
		nickname = logLine.nickname
		nicknameColorStyle = logLine.nicknameColorStyle
		nicknameColorStyleOverride = logLine.nicknameColorStyleOverride
		messageIdentifier = logLine.messageIdentifier
		replyToMessageIdentifier = logLine.replyToMessageIdentifier
		deliveryStateString = logLine.deliveryStateString
		reactions = logLine.reactions
		highlightKeywords = logLine.highlightKeywords
		excludeKeywords = logLine.excludeKeywords
		doNotEscapeBody = (LogRendererConfiguration(rawValues: logLine.rendererAttributes ?? [:])[
			.doNotEscapeBody
		] as? NSNumber)?.boolValue == true
		isEncrypted = logLine.isEncrypted
		isFirstForDay = logLine.isFirstForDay
		sourceDescription = logLine.description

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

/// One log line together with the context it is rendered in.
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

/** What the plugins are told about a line that was posted.

 The concrete object the plugin API takes holds `ChannelUser` and
 `LinkParserResult` references and is built on the main actor, where the
 nicknames the body mentioned can be resolved against the live member list. */
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
		let pluginObject = THOPluginDidPostNewMessageConcreteObject()
		pluginObject.keywordMatchFound = keywordMatchFound
		pluginObject.lineTypeRawValue = lineTypeRawValue
		pluginObject.memberTypeRawValue = memberTypeRawValue
		pluginObject.senderNickname = senderNickname
		pluginObject.receivedAt = receivedAt
		pluginObject.lineNumber = lineNumber
		pluginObject.messageContents = messageContents
		pluginObject.hyperlinks = hyperlinks
		pluginObject.users = nicknames.compactMap { channel?.findMember($0) }
		return pluginObject
	}
}

/// Everything the main actor needs in order to apply a rendered log line.
nonisolated struct LogLineRenderResult: Sendable { // nonisolated: value
	var lineNumber: String
	var html: String
	var timestamp: TimeInterval
	var isHighlight: Bool
	var processesInlineMedia: Bool
	var links: [LinkParserResult] = []
	/** Nicknames the body mentioned. Resolved back to members on the main
	 actor: the member list may have changed while the line rendered. */
	var mentionedNicknames: [String] = []
	var pluginMessage: RenderedPluginMessage?
}

/// The two pieces of rendering that need a live theme and the renderer's view
/// context. Injected so that the request-to-result round trip can be exercised
/// without either of them.
nonisolated protocol LogLineRendering: Sendable { // nonisolated: value
	func renderBody(
		_ body: String,
		attributes: [String: Any],
		members: [RenderedMember],
		results: inout [String: Any]
	) -> String
	func renderTemplate(for lineType: TVCLogLineType, attributes: ThemeTemplateAttributes) -> String?
}

/// Renders through `TVCLogRenderer` and the theme that is active right now.
/// Stateless: everything a line needs travels in its request.
nonisolated struct ThemeLogLineRenderer: LogLineRendering { // nonisolated: value
	func renderBody(
		_ body: String,
		attributes: [String: Any],
		members: [RenderedMember],
		results: inout [String: Any]
	) -> String {
		TVCLogRenderer.renderBody(
			body,
			withAttributes: attributes,
			members: members,
			results: &results
		)
	}

	func renderTemplate(for lineType: TVCLogLineType, attributes: ThemeTemplateAttributes) -> String? {
		/* A theme reload nils the active theme out from under the pipeline.
		 Skip the line instead of trapping on it. */
		guard let theme = ThemeController.activeSnapshot?.theme,
		      let template = theme.template(withLineType: lineType)
		else {
			return nil
		}
		return TVCLogRenderer.renderTemplate(template, attributes: attributes)
	}
}

extension LogController {
	/** Takes the render snapshot of `logLine` with the message-renderer plugin
	 hook applied to its body.

	 The hook is the one plugin dispatch that is not main-actor, and it ignores
	 the view controller it is handed. Passing the controller through is
	 therefore safe from any domain — it is a reference to a main-actor class,
	 which is `Sendable`, and nothing here touches its state. */
	nonisolated static func makeSnapshot(
		of logLine: LogLine,
		in context: LogLineRenderContext,
		for viewController: LogController
	) -> LogLineSnapshot {
		var snapshot = LogLineSnapshot(logLine, in: context)
		snapshot.messageBody = PluginDispatcher.willRenderMessage(
			snapshot.messageBody,
			forViewController: viewController,
			lineType: snapshot.lineType,
			memberType: snapshot.memberType
		)
		return snapshot
	}

	/// Renders every line of `lines`, skipping the ones that fail.
	nonisolated static func render(
		_ lines: [LogLineSnapshot],
		context: LogLineRenderContext,
		using renderer: some LogLineRendering
	) -> [LogLineRenderResult] {
		lines.compactMap { line in
			guard let result = render(LogLineRenderRequest(line: line, context: context), using: renderer)
			else {
				logLineRenderingLogger
					.error("Failed to render log line \(line.sourceDescription, privacy: .public)")
				return nil
			}
			return result
		}
	}

	/// Turns a request into the HTML and the results the main actor acts on.
	/// Runs off the main actor.
	nonisolated static func render(
		_ request: LogLineRenderRequest,
		using renderer: some LogLineRendering
	) -> LogLineRenderResult? {
		let line = request.line
		let lineType = line.lineType
		let lineTypeString = line.lineTypeString ?? ""
		let renderLinks = !LinkParser.bannedLineTypes.contains(lineTypeString)
		var rendererAttributes = LogRendererConfiguration()
		if line.doNotEscapeBody {
			rendererAttributes[.doNotEscapeBody] = true
		}
		if let excludeKeywords = line.excludeKeywords {
			rendererAttributes[.excludedKeywords] = excludeKeywords
		}
		if let highlightKeywords = line.highlightKeywords {
			rendererAttributes[.highlightKeywords] = highlightKeywords
		}
		rendererAttributes[.renderLinks] = renderLinks
		rendererAttributes[.lineType] = lineType.rawValue
		rendererAttributes[.memberType] = line.memberType.rawValue
		rendererAttributes[.inlineMediaEnabled] = request.context.inlineMediaEnabled

		var rawResults: [String: Any] = [:]
		let renderedBody = renderer.renderBody(
			line.messageBody,
			attributes: rendererAttributes.rawValues,
			members: request.context.members,
			results: &rawResults
		)
		let results = LogRendererResults(rawValues: rawResults)
		let highlighted = (results[.keywordMatchFound] as? NSNumber)?.boolValue ?? false
		let inlineMedia = request.context.inlineMediaEnabled &&
			(lineType == .privateMessage || lineType == .action)
		guard let html = renderer.renderTemplate(
			for: lineType,
			attributes: templateAttributes(
				for: request,
				renderedBody: renderedBody,
				highlighted: highlighted,
				inlineMedia: inlineMedia
			)
		) else {
			return nil
		}
		let nicknames = results.value(for: .users, as: [String].self) ?? []
		return LogLineRenderResult(
			lineNumber: line.uniqueIdentifier,
			html: html,
			timestamp: line.receivedAt.timeIntervalSince1970,
			isHighlight: highlighted,
			processesInlineMedia: inlineMedia,
			links: results.value(for: .links, as: [LinkParserResult].self) ?? [],
			mentionedNicknames: nicknames,
			pluginMessage: makePluginMessage(
				for: line,
				results: results,
				nicknames: nicknames,
				highlighted: highlighted
			)
		)
	}

	private nonisolated static func templateAttributes(
		for request: LogLineRenderRequest,
		renderedBody: String,
		highlighted: Bool,
		inlineMedia: Bool
	) -> ThemeTemplateAttributes {
		let line = request.line
		let context = request.context
		let lineType = line.lineType
		let receivedAt = line.receivedAt
		let lineNumber = line.uniqueIdentifier
		let lineClass: LogLineClassToken = if lineType == .privateMessage || lineType == .action || lineType ==
			.notice
		{
			.text
		} else {
			.event
		}
		var attributes: ThemeTemplateAttributes = [
			.activeStyleAbsolutePath: context.styleAbsolutePath,
			.applicationResourcePath: PathInfo.applicationResources,
			.timestamp: receivedAt.timeIntervalSince1970,
			.formattedTimestamp: line.formattedTimestamp,
			.localizedTimestamp: formatDateLongStyle(receivedAt, false) ?? "",
			.lineType: line.lineTypeString ?? "",
			.command: line.command,
			.rawCommand: line.command,
			.lineClassAttribute: lineClass.rawValue,
			.highlightAttribute: String(highlighted),
			.message: line.messageBody,
			.formattedMessage: renderedBody,
			.isHighlight: highlighted,
			.isRemoteMessage: line.memberType == .normal,
			.inlineMediaEnabled: inlineMedia,
			.lineNumber: lineNumber,
			.lineRenderTime: Date().timeIntervalSince1970,
			.configuredServerName: context.networkName,
		]
		attributes.merge(nicknameAttributes(for: line))
		if let messageIdentifier = line.messageIdentifier, !messageIdentifier.isEmpty {
			attributes[.messageIdentifier] = messageIdentifier
		}
		if let deliveryState = line.deliveryStateString {
			attributes[.deliveryState] = deliveryState
		}
		if let replyIdentifier = line.replyToMessageIdentifier, !replyIdentifier.isEmpty {
			attributes[.replyToMessageIdentifier] = replyIdentifier
		}
		if let reactions = context.reactions(for: line),
		   let data = try? JSONEncoder().encode(reactions),
		   let json = String(data: data, encoding: .utf8)
		{
			attributes[.reactionsJSON] = json
		}
		if line.isEncrypted {
			attributes[.isEncrypted] = true
		}
		if line.isFirstForDay, TextualPreferences.showDateChanges() {
			attributes[.showDateIndicator] = true
			attributes[.dateIndicatorMessage] = formatDate(receivedAt, .long, .none, false) ?? ""
		}
		if lineNumber == context.sessionIndicatorLineNumber {
			attributes[.showSessionIndicator] = true
			attributes[.sessionIndicatorMessage] = MainWindowStrings.Conversation.currentSession
		}
		return attributes
	}

	private nonisolated static func nicknameAttributes(
		for line: LogLineSnapshot
	) -> ThemeTemplateAttributes {
		/* The sender was formatted on the main actor, when the snapshot was
		 taken, because the mode symbol comes from the live member list. */
		guard line.formattedNickname.isEmpty == false else {
			return [.isNicknameAvailable: false]
		}
		return [
			.isNicknameAvailable: true,
			.nicknameColorStyle: line.nicknameColorStyle,
			.nicknameColorStyleOverride: line.nicknameColorStyleOverride,
			.nicknameColorHashingEnabled: !TextualPreferences.disableNicknameColorHashing(),
			.formattedNickname: line.formattedNickname,
			.nickname: line.nickname ?? "",
			.nicknameType: line.memberTypeString,
		]
	}

	private nonisolated static func makePluginMessage(
		for line: LogLineSnapshot,
		results: LogRendererResults,
		nicknames: [String],
		highlighted: Bool
	) -> RenderedPluginMessage? {
		guard SharedApplication.sharedPluginManager().supportsFeature(.newMessagePostedEvent) else {
			return nil
		}
		return RenderedPluginMessage(
			keywordMatchFound: highlighted,
			lineTypeRawValue: line.lineType.rawValue,
			memberTypeRawValue: line.memberType.rawValue,
			senderNickname: line.nickname,
			receivedAt: line.receivedAt,
			lineNumber: line.uniqueIdentifier,
			messageContents: results.value(for: .bodyWithoutEffects, as: String.self) ?? "",
			hyperlinks: results.value(for: .links, as: [LinkParserResult].self) ?? [],
			nicknames: nicknames
		)
	}
}
