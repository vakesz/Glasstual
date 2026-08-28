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

import AppKit
import CocoaExtensions
import Foundation
import GlasstualPluginKit
import os

private let logLineRenderingLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogLineRendering"
)

/// The main-actor state that every line rendered by one printing operation
/// needs. Captured on the main actor before the operation is enqueued so that
/// rendering never reaches back into the controller for it.
struct LogLineRenderContext {
	var channel: IRCChannel?
	var networkName = ""
	var styleAbsolutePath = ""
	var inlineMediaEnabled = false
	/// Line number that carries the "current session" marker, if any.
	var sessionIndicatorLineNumber: String?
	/// Reactions received during this session, keyed by message identifier.
	var sessionReactions: [String: [String: [String]]] = [:]

	/// Merges the reactions archived with the line and those seen this session.
	func reactions(for logLine: LogLine) -> [String: [String]]? {
		let archived = logLine.reactions
		let session = logLine.messageIdentifier.flatMap { sessionReactions[$0] }
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

/// One log line together with the context it is rendered in.
struct LogLineRenderRequest {
	var logLine: LogLine
	var context: LogLineRenderContext
}

/// Everything the main actor needs in order to apply a rendered log line.
struct LogLineRenderResult {
	var lineNumber: String
	var html: String
	var timestamp: TimeInterval
	var isHighlight: Bool
	var processesInlineMedia: Bool
	var links: [LinkParserResult] = []
	var users: Set<ChannelUser> = []
	var pluginObject: THOPluginDidPostNewMessageConcreteObject?
}

/// The two pieces of rendering that need a live theme and the renderer's view
/// context. Injected so that the request-to-result round trip can be exercised
/// without either of them.
protocol LogLineRendering {
	func renderBody(_ body: String, attributes: [String: Any], results: inout [String: Any]) -> String
	func renderTemplate(for lineType: TVCLogLineType, attributes: ThemeTemplateAttributes) -> String?
}

/// Renders through `TVCLogRenderer` and the theme that is active right now.
struct ThemeLogLineRenderer: LogLineRendering {
	let viewController: LogController

	func renderBody(_ body: String, attributes: [String: Any], results: inout [String: Any]) -> String {
		var rendererResults: NSDictionary?
		let rendered = TVCLogRenderer.renderBody(
			body,
			forViewController: viewController,
			withAttributes: attributes,
			resultInfo: &rendererResults
		)
		results = rendererResults as? [String: Any] ?? [:]
		return rendered
	}

	func renderTemplate(for lineType: TVCLogLineType, attributes: ThemeTemplateAttributes) -> String? {
		/* A theme reload nils the active theme out from under the printing
		 queue. Skip the line instead of trapping on it. */
		guard let theme = SharedApplication.sharedThemeController().theme,
		      let template = theme.template(withLineType: lineType)
		else {
			return nil
		}
		return TVCLogRenderer.renderTemplate(template, attributes: attributes)
	}
}

extension LogController {
	/// Renders every line of `logLines`, skipping the ones that fail.
	nonisolated static func render(
		_ logLines: [LogLine],
		context: LogLineRenderContext,
		using renderer: some LogLineRendering
	) -> [LogLineRenderResult] {
		logLines.compactMap { logLine in
			guard let result = render(LogLineRenderRequest(logLine: logLine, context: context), using: renderer)
			else {
				logLineRenderingLogger.error("Failed to render log line \(logLine.description, privacy: .public)")
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
		let logLine = request.logLine
		let lineType = logLine.lineType
		let lineTypeString = logLine.lineTypeString ?? ""
		let renderLinks = !LinkParser.bannedLineTypes.contains(lineTypeString)
		var rendererAttributes = LogRendererConfiguration(rawValues: logLine.rendererAttributes ?? [:])
		if let excludeKeywords = logLine.excludeKeywords {
			rendererAttributes[.excludedKeywords] = excludeKeywords
		}
		if let highlightKeywords = logLine.highlightKeywords {
			rendererAttributes[.highlightKeywords] = highlightKeywords
		}
		rendererAttributes[.renderLinks] = renderLinks
		rendererAttributes[.lineType] = lineType.rawValue
		rendererAttributes[.memberType] = logLine.memberType.rawValue

		var rawResults: [String: Any] = [:]
		let renderedBody = renderer.renderBody(
			logLine.messageBody,
			attributes: rendererAttributes.rawValues,
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
		return LogLineRenderResult(
			lineNumber: logLine.uniqueIdentifier,
			html: html,
			timestamp: logLine.receivedAt.timeIntervalSince1970,
			isHighlight: highlighted,
			processesInlineMedia: inlineMedia,
			links: results.value(for: .links, as: [LinkParserResult].self) ?? [],
			users: results.value(for: .users, as: Set<ChannelUser>.self) ?? [],
			pluginObject: makePluginObject(for: logLine, results: results, highlighted: highlighted)
		)
	}

	private nonisolated static func templateAttributes(
		for request: LogLineRenderRequest,
		renderedBody: String,
		highlighted: Bool,
		inlineMedia: Bool
	) -> ThemeTemplateAttributes {
		let logLine = request.logLine
		let context = request.context
		let lineType = logLine.lineType
		let receivedAt = logLine.receivedAt
		let lineNumber = logLine.uniqueIdentifier
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
			.formattedTimestamp: logLine.formattedTimestamp,
			.localizedTimestamp: formatDateLongStyle(receivedAt, false) ?? "",
			.lineType: logLine.lineTypeString ?? "",
			.command: logLine.command,
			.rawCommand: logLine.command,
			.lineClassAttribute: lineClass.rawValue,
			.highlightAttribute: String(highlighted),
			.message: logLine.messageBody,
			.formattedMessage: renderedBody,
			.isHighlight: highlighted,
			.isRemoteMessage: logLine.memberType == .normal,
			.inlineMediaEnabled: inlineMedia,
			.lineNumber: lineNumber,
			.lineRenderTime: Date().timeIntervalSince1970,
			.configuredServerName: context.networkName,
		]
		attributes.merge(nicknameAttributes(for: logLine, in: context.channel))
		if let messageIdentifier = logLine.messageIdentifier, !messageIdentifier.isEmpty {
			attributes[.messageIdentifier] = messageIdentifier
		}
		if let deliveryState = logLine.deliveryStateString {
			attributes[.deliveryState] = deliveryState
		}
		if let replyIdentifier = logLine.replyToMessageIdentifier, !replyIdentifier.isEmpty {
			attributes[.replyToMessageIdentifier] = replyIdentifier
		}
		if let reactions = context.reactions(for: logLine),
		   let data = try? JSONEncoder().encode(reactions),
		   let json = String(data: data, encoding: .utf8)
		{
			attributes[.reactionsJSON] = json
		}
		if logLine.isEncrypted {
			attributes[.isEncrypted] = true
		}
		if logLine.isFirstForDay, TextualPreferences.showDateChanges() {
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
		for logLine: LogLine,
		in channel: IRCChannel?
	) -> ThemeTemplateAttributes {
		let nickname = logLine.formattedNickname(in: channel)?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard nickname.isEmpty == false else {
			return [.isNicknameAvailable: false]
		}
		return [
			.isNicknameAvailable: true,
			.nicknameColorStyle: logLine.nicknameColorStyle,
			.nicknameColorStyleOverride: logLine.nicknameColorStyleOverride,
			.nicknameColorHashingEnabled: !TextualPreferences.disableNicknameColorHashing(),
			.formattedNickname: nickname,
			.nickname: logLine.nickname ?? "",
			.nicknameType: logLine.memberTypeString,
		]
	}

	private nonisolated static func makePluginObject(
		for logLine: LogLine,
		results: LogRendererResults,
		highlighted: Bool
	) -> THOPluginDidPostNewMessageConcreteObject? {
		guard SharedApplication.sharedPluginManager().supportsFeature(.newMessagePostedEvent) else {
			return nil
		}
		let pluginObject = THOPluginDidPostNewMessageConcreteObject()
		pluginObject.keywordMatchFound = highlighted
		pluginObject.lineTypeRawValue = logLine.lineType.rawValue
		pluginObject.memberTypeRawValue = logLine.memberType.rawValue
		pluginObject.senderNickname = logLine.nickname
		pluginObject.receivedAt = logLine.receivedAt
		pluginObject.lineNumber = logLine.uniqueIdentifier
		pluginObject.messageContents = results.value(for: .bodyWithoutEffects, as: String.self) ?? ""
		pluginObject.hyperlinks = results.value(for: .links, as: [LinkParserResult].self) ?? []
		pluginObject.users = Array(results.value(for: .users, as: Set<ChannelUser>.self) ?? [])
		return pluginObject
	}
}
