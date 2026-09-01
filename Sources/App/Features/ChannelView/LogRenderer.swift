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

import AppKit
import CocoaExtensions
import Foundation
import OSLog

private nonisolated let rendererLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogRenderer"
)

private nonisolated enum RendererPatterns { // nonisolated: value
	static let combiningMarks = compile("[\\p{InCombining_Diacritical_Marks}]{3,}")
	static let channelName = compile("#([a-zA-Z0-9\\#\\-]+)")

	private static func compile(_ pattern: String) -> NSRegularExpression? {
		do {
			return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
		} catch {
			rendererLogger.fault("Renderer pattern '\(pattern, privacy: .public)' did not compile")
			return nil
		}
	}
}

nonisolated enum RendererFormatting { // nonisolated: value
	static let foregroundColor = NSAttributedString.Key("TVCLogRendererFormattingForegroundColorAttribute")
	static let backgroundColor = NSAttributedString.Key("TVCLogRendererFormattingBackgroundColorAttribute")
	static let bold = NSAttributedString.Key("TVCLogRendererFormattingBoldTextAttribute")
	static let italic = NSAttributedString.Key("TVCLogRendererFormattingItalicTextAttribute")
	static let monospace = NSAttributedString.Key("TVCLogRendererFormattingMonospaceTextAttribute")
	static let strikethrough = NSAttributedString.Key("TVCLogRendererFormattingStrikethroughTextAttribute")
	static let underline = NSAttributedString.Key("TVCLogRendererFormattingUnderlineTextAttribute")
	static let channelName = NSAttributedString.Key("TVCLogRendererFormattingChannelNameAttribute")
	static let conversationTracking = NSAttributedString.Key("TVCLogRendererFormattingConversationTrackingAttribute")
	static let keywordHighlight = NSAttributedString.Key("TVCLogRendererFormattingKeywordHighlightAttribute")
	static let url = NSAttributedString.Key("TVCLogRendererFormattingURLAttribute")
}

/// Parses IRC control codes and annotates semantic runs for the native
/// transcript. It never produces markup or holds a reference to a view.
public nonisolated struct LogRenderer { // nonisolated: value
	private var body = ""
	private var attributedBody = NSMutableAttributedString()
	private var configuration = LogRendererConfiguration()
	private var members: [RenderedMember] = []
	private var lineType = TVCLogLineType.undefined
	private var memberType = TVCLogLineMemberType.normal
	private var links: [LinkParserResult] = []
	private var mentionedNicknames: [String] = []
	private var isHighlight = false

	private var isMessage: Bool {
		lineType == .privateMessage || lineType == .action
	}

	private var isMessageOrNotice: Bool {
		isMessage || lineType == .notice
	}

	private mutating func parseFormatting() {
		attributedBody = IRCFormattingParser.parse(body)
		body = attributedBody.string
	}

	private mutating func filterUnicodeSpam() {
		guard Preferences.Messages.filterUnicodeTextSpam.detachedValue else { return }
		let filteredTypes: Set<TVCLogLineType> = [
			.action, .ctcp, .ctcpQuery, .ctcpReply, .dccFileTransfer, .notice, .privateMessage, .topic,
		]
		guard filteredTypes.contains(lineType) else { return }
		body = Self.strippingDangerousUnicodeCharacters(body)
	}

	static func strippingDangerousUnicodeCharacters(_ text: String) -> String {
		guard let expression = RendererPatterns.combiningMarks else { return text }
		return expression.stringByReplacingMatches(
			in: text,
			range: NSRange(location: 0, length: (text as NSString).length),
			withTemplate: unicodeReplacementCharacter
		)
	}

	private mutating func annotateLinks() {
		guard configuration.bool(for: .renderLinks) else { return }
		links = LinkParser.locateLinks(in: body)
		for link in links {
			attributedBody.addAttribute(RendererFormatting.url, value: link, range: link.range)
		}
	}

	private mutating func annotateHighlight() {
		guard isMessage, memberType == .normal else { return }
		let highlighted = configuration.value(for: .highlightKeywords, as: [String].self) ?? []
		guard highlighted.isEmpty == false else { return }
		let excluded = configuration.value(for: .excludedKeywords, as: [String].self) ?? []
		let excludedRanges = excluded.flatMap { ranges(of: $0, options: .caseInsensitive) }
		let matchMethod = Preferences.Highlights.matchingMethod.detachedValue

		for keyword in highlighted where isHighlight == false {
			let matches = matchMethod == .regularExpression
				? Array(ranges(ofRegularExpression: keyword).prefix(1))
				: ranges(of: keyword, options: .caseInsensitive)
			for range in matches {
				guard excludedRanges.allSatisfy({ NSIntersectionRange(range, $0).length == 0 }) else { continue }
				if matchMethod == .exact, isSurroundedByNonAlphanumerics(range) == false {
					continue
				}
				guard attributedBody.attribute(RendererFormatting.url, at: range.location, effectiveRange: nil) == nil
				else { continue }
				attributedBody.addAttribute(RendererFormatting.keywordHighlight, value: true, range: range)
				isHighlight = true
				break
			}
		}
	}

	private mutating func annotateChannels() {
		guard isMessageOrNotice, let expression = RendererPatterns.channelName else { return }
		for range in ranges(of: expression) {
			guard isSurroundedByNonAlphanumerics(range),
			      attributedBody.attribute(RendererFormatting.url, at: range.location, effectiveRange: nil) == nil
			else { continue }
			attributedBody.addAttribute(RendererFormatting.channelName, value: true, range: range)
		}
	}

	private mutating func annotateMembers() {
		guard isMessage, body.isEmpty == false, members.isEmpty == false else { return }
		var nicknameCount = 0
		var nicknameLength = 0

		for member in members {
			for range in ranges(of: member.nickname, options: .caseInsensitive) {
				guard isSurroundedByNonAlphanumerics(range),
				      attributedBody.attribute(RendererFormatting.url, at: range.location, effectiveRange: nil) == nil
				else { continue }
				attributedBody.addAttribute(RendererFormatting.conversationTracking, value: true, range: range)
				if mentionedNicknames.contains(member.nickname) == false {
					mentionedNicknames.append(member.nickname)
				}
				if attributedBody.attribute(
					RendererFormatting.keywordHighlight,
					at: range.location,
					effectiveRange: nil
				)
					== nil
				{
					nicknameCount += 1
					nicknameLength += range.length
				}
			}
		}

		if Preferences.Messages.detectHighlightSpam.detachedValue {
			let percent = Double(nicknameLength) / Double((body as NSString).length) * 100
			if percent > 75 && nicknameCount > 10 || percent > 50 && nicknameCount > 20 {
				isHighlight = false
			}
		}
	}

	private func ranges(of search: String, options: NSString.CompareOptions) -> [NSRange] {
		guard search.isEmpty == false else { return [] }
		let source = body as NSString
		var remaining = NSRange(location: 0, length: source.length)
		var result: [NSRange] = []
		while remaining.length > 0 {
			let match = source.range(of: search, options: options, range: remaining)
			guard match.location != NSNotFound else { break }
			result.append(match)
			let next = NSMaxRange(match)
			remaining = NSRange(location: next, length: source.length - next)
		}
		return result
	}

	private func ranges(ofRegularExpression pattern: String) -> [NSRange] {
		guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
		return ranges(of: expression)
	}

	private func ranges(of expression: NSRegularExpression) -> [NSRange] {
		expression.matches(
			in: body,
			range: NSRange(location: 0, length: (body as NSString).length)
		).map(\.range)
	}

	private func isSurroundedByNonAlphanumerics(_ range: NSRange) -> Bool {
		let source = body as NSString
		guard range.length > 0, range.location < source.length, NSMaxRange(range) <= source.length else { return false }
		func isAlphanumeric(_ character: UniChar) -> Bool {
			character >= 48 && character <= 57 || UnicodeHelper.isAlphabeticalCodePoint(Int(character))
		}
		if range.location > 0,
		   isAlphanumeric(source.character(at: range.location)),
		   isAlphanumeric(source.character(at: range.location - 1))
		{
			return false
		}
		let right = NSMaxRange(range)
		if right < source.length,
		   isAlphanumeric(source.character(at: right - 1)),
		   isAlphanumeric(source.character(at: right))
		{
			return false
		}
		return true
	}

	private func member(named nickname: String) -> RenderedMember? {
		members.first { $0.nickname.caseInsensitiveCompare(nickname) == .orderedSame }
	}

	private func result() -> TranscriptBody {
		let source = attributedBody.string as NSString
		var runs: [TranscriptTextRun] = []
		attributedBody.enumerateAttributes(
			in: NSRange(location: 0, length: attributedBody.length)
		) { attributes, range, _ in
			var traits = TranscriptTextTraits()
			if attributes[RendererFormatting.bold] != nil {
				traits.insert(.bold)
			}
			if attributes[RendererFormatting.italic] != nil {
				traits.insert(.italic)
			}
			if attributes[RendererFormatting.monospace] != nil {
				traits.insert(.monospace)
			}
			if attributes[RendererFormatting.strikethrough] != nil {
				traits.insert(.strikethrough)
			}
			if attributes[RendererFormatting.underline] != nil {
				traits.insert(.underline)
			}
			if attributes[RendererFormatting.keywordHighlight] != nil {
				traits.insert(.highlighted)
			}

			let text = source.substring(with: range)
			let action: TranscriptRunAction? = if let link = attributes[RendererFormatting.url]
				as? LinkParserResult,
				Self.isSafeLink(link.stringValue),
				let url = URL(string: link.stringValue)
			{
				.link(url)
			} else if attributes[RendererFormatting.channelName] != nil {
				.channel(text)
			} else if attributes[RendererFormatting.conversationTracking] != nil {
				.nickname(member(named: text)?.nickname ?? text)
			} else {
				nil
			}

			runs.append(TranscriptTextRun(
				text: text,
				traits: traits,
				foreground: Self.nativeColor(attributes[RendererFormatting.foregroundColor]),
				background: Self.nativeColor(attributes[RendererFormatting.backgroundColor]),
				action: action
			))
		}
		return TranscriptBody(
			plainText: body,
			runs: runs,
			links: links,
			mentionedNicknames: mentionedNicknames,
			isHighlight: isHighlight
		)
	}

	private static let refusedLinkSchemes: Set<String> = [
		"javascript", "data", "vbscript", "blob", "filesystem", "about",
	]

	static func isSafeLink(_ location: String) -> Bool {
		guard let url = URL(string: location), let scheme = url.scheme?.lowercased() else { return false }
		return refusedLinkSchemes.contains(scheme) == false && LinkParser.isPermittedScheme(scheme)
	}

	private static func nativeColor(_ value: Any?) -> TranscriptRunColor? {
		if let index = value as? NSNumber {
			return .palette(index.intValue)
		}
		guard let color = value as? NSColor, let components = TranscriptThemeColor(color) else { return nil }
		return .rgb(components)
	}
}

public extension LogRenderer {
	internal nonisolated static func renderNativeBody( // nonisolated: pure
		_ body: String,
		withAttributes configuration: LogRendererConfiguration,
		members: [RenderedMember]
	) -> TranscriptBody {
		guard body.isEmpty == false else { return TranscriptBody() }
		var renderer = LogRenderer()
		renderer.lineType = TVCLogLineType(
			rawValue: configuration.value(for: .lineType, as: UInt.self) ?? 0
		) ?? .undefined
		renderer.memberType = TVCLogLineMemberType(
			rawValue: configuration.value(for: .memberType, as: UInt.self) ?? 0
		) ?? .normal
		renderer.body = body
		renderer.configuration = configuration
		renderer.members = members
		renderer.filterUnicodeSpam()
		renderer.parseFormatting()
		renderer.annotateLinks()
		renderer.annotateHighlight()
		renderer.annotateChannels()
		renderer.annotateMembers()
		return renderer.result()
	}

	@MainActor
	internal static func renderBody(
		asAttributedString body: String,
		withAttributes configuration: LogRendererConfiguration
	) -> NSAttributedString {
		let parsed = IRCFormattingParser.parse(body)
		let result = NSMutableAttributedString(attributedString: parsed)
		parsed.enumerateAttributes(in: NSRange(location: 0, length: parsed.length)) { attributes, range, _ in
			result.addAttributes(appKitAttributes(from: attributes, configuration: configuration), range: range)
		}
		return result
	}

	@MainActor
	private static func appKitAttributes(
		from attributes: [NSAttributedString.Key: Any],
		configuration: LogRendererConfiguration
	) -> [NSAttributedString.Key: Any] {
		var result: [NSAttributedString.Key: Any] = [:]
		let defaultFont = configuration.value(for: .preferredFont, as: NSFont.self)
		let defaultColor = configuration.value(for: .preferredFontColor, as: NSColor.self)
		var font = defaultFont
		if attributes[RendererFormatting.monospace] != nil, let current = font {
			font = NSFontManager.shared.convert(current, toFamily: "Menlo")
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.monospaceAttributeName.rawValue)] = true
		}
		if attributes[RendererFormatting.bold] != nil, let current = font {
			font = NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.boldAttributeName.rawValue)] = true
		}
		if attributes[RendererFormatting.italic] != nil, let current = font {
			font = NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.italicAttributeName.rawValue)] = true
		}
		result[.font] = font
		if attributes[RendererFormatting.strikethrough] != nil {
			result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.strikethroughAttributeName.rawValue)] = true
		}
		if attributes[RendererFormatting.underline] != nil {
			result[.underlineStyle] = NSUnderlineStyle.single.rawValue
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.underlineAttributeName.rawValue)] = true
		}
		if let foreground = attributes[RendererFormatting.foregroundColor] {
			result[.foregroundColor] = mapColor(foreground)
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue)] =
				foreground
		} else if let defaultColor {
			result[.foregroundColor] = defaultColor
		}
		if let background = attributes[RendererFormatting.backgroundColor] {
			result[.backgroundColor] = mapColor(background)
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue)] =
				background
		}
		return result.compactMapValues { $0 }
	}

	nonisolated static func mapColor(_ color: Any) -> NSColor? { // nonisolated: pure
		if let color = color as? NSColor {
			return color
		}
		if let color = color as? NSNumber {
			return mapColorCode(color.uintValue)
		}
		return nil
	}

	nonisolated static func mapColorCode(_ colorCode: UInt) -> NSColor { // nonisolated: pure
		precondition(colorCode <= IRCTextFormatterColor.maximumPaletteIndex)
		return NSColor.formatterColors[Int(colorCode)]
	}
}
