// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import OSLog

private nonisolated let rendererLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "TranscriptRenderer"
)

private nonisolated enum RendererPatterns {
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

/** The marks the formatting parser leaves on the string it hands the renderer.

 They live on a transient `NSMutableAttributedString` that never leaves this
 file's call chain: nothing persists them and the names carry no compatibility
 requirement. */
nonisolated enum RendererFormatting {
	static let foregroundColor = NSAttributedString.Key("GlasstualRendererForegroundColor")
	static let backgroundColor = NSAttributedString.Key("GlasstualRendererBackgroundColor")
	static let bold = NSAttributedString.Key("GlasstualRendererBold")
	static let italic = NSAttributedString.Key("GlasstualRendererItalic")
	static let monospace = NSAttributedString.Key("GlasstualRendererMonospace")
	static let strikethrough = NSAttributedString.Key("GlasstualRendererStrikethrough")
	static let underline = NSAttributedString.Key("GlasstualRendererUnderline")
	static let channelName = NSAttributedString.Key("GlasstualRendererChannelName")
	static let conversationTracking = NSAttributedString.Key("GlasstualRendererConversationTracking")
	static let keywordHighlight = NSAttributedString.Key("GlasstualRendererKeywordHighlight")
	static let url = NSAttributedString.Key("GlasstualRendererURL")
}

/// Parses IRC control codes and annotates semantic runs for the native
/// transcript. It never produces markup or holds a reference to a view.
nonisolated struct TranscriptRenderer {
	/* The attributed text the annotation steps mark up is a reference, so it is
	 threaded through them as an argument rather than stored here: a renderer
	 that held one could not honestly call itself a value. It never leaves this
	 file's call chain — `result(from:)` projects it into the `Sendable`
	 `TranscriptBody` the transcript draws. */
	private let configuration: TranscriptRenderOptions
	private let members: RenderedMemberDirectory
	private var body: String
	private var links: [LinkParserResult] = []
	private var mentionedNicknames: [String] = []
	private var isHighlight = false

	init(body: String, configuration: TranscriptRenderOptions, members: RenderedMemberDirectory) {
		self.body = body
		self.configuration = configuration
		self.members = members.caseMapping == configuration.caseMapping
			? members
			: RenderedMemberDirectory(members.members, caseMapping: configuration.caseMapping)
	}

	private var lineType: ChatLineKind {
		configuration.lineType
	}

	private var memberType: ChatLineMemberKind {
		configuration.memberType
	}

	private var policy: TranscriptTextRules {
		configuration.textPolicy
	}

	private var isMessage: Bool {
		lineType == .privateMessage || lineType == .action
	}

	private var isMessageOrNotice: Bool {
		isMessage || lineType == .notice
	}

	/// Parses the control codes, returning the attributed text the annotation
	/// steps mark up.
	private mutating func parseFormatting() -> NSMutableAttributedString {
		let attributedBody = FormattingParser.parse(body)
		body = attributedBody.string

		return attributedBody
	}

	private mutating func filterUnicodeSpam() {
		guard policy.filtersUnicodeTextSpam else { return }
		let filteredTypes: Set<ChatLineKind> = [
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

	private mutating func annotateLinks(in attributedBody: NSMutableAttributedString) {
		guard configuration.renderLinks else { return }
		links = LinkParser.locateLinks(in: body, allowing: policy.linkSchemes)
		for link in links {
			attributedBody.addAttribute(RendererFormatting.url, value: link, range: link.range)
		}
	}

	private mutating func annotateHighlight(in attributedBody: NSMutableAttributedString) {
		guard isMessage, memberType == .normal else { return }
		let highlighted = configuration.highlightKeywords
		guard highlighted.isEmpty == false else { return }
		let excluded = configuration.excludedKeywords
		let excludedRanges = excluded.flatMap { ranges(of: $0, options: .caseInsensitive) }
		let matchMethod = policy.highlightMatchingMethod

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

	private func annotateChannels(in attributedBody: NSMutableAttributedString) {
		guard isMessageOrNotice, let expression = RendererPatterns.channelName else { return }
		/* The whole line, not the first four kilobytes of it: that cap is for
		 the patterns the reader writes, and this one is the renderer's own --
		 a bounded alternation that cannot backtrack. Sharing the cap meant a
		 channel named past the cap in a long line was not a link, while the
		 same name a line earlier was. */
		for range in ranges(of: expression, matchedLength: (body as NSString).length) {
			guard isSurroundedByNonAlphanumerics(range),
			      attributedBody.attribute(RendererFormatting.url, at: range.location, effectiveRange: nil) == nil
			else { continue }
			attributedBody.addAttribute(
				RendererFormatting.channelName,
				value: (body as NSString).substring(with: range),
				range: range
			)
		}
	}

	private mutating func annotateMembers(in attributedBody: NSMutableAttributedString) {
		guard isMessage, body.isEmpty == false, members.isEmpty == false else { return }
		var nicknameCount = 0
		var nicknameLength = 0

		for reference in TranscriptMemberReference.locate(in: body, members: members) {
			let range = reference.range
			guard attributedBody.attribute(RendererFormatting.url, at: range.location, effectiveRange: nil) == nil
			else { continue }
			if reference.isExplicitMention {
				attributedBody.addAttribute(
					RendererFormatting.conversationTracking,
					value: reference.nickname,
					range: range
				)
				if mentionedNicknames.contains(reference.nickname) == false {
					mentionedNicknames.append(reference.nickname)
				}
			}
			if attributedBody.attribute(RendererFormatting.keywordHighlight, at: range.location, effectiveRange: nil) == nil {
				nicknameCount += 1
				nicknameLength += range.length
			}
		}

		if policy.detectsHighlightSpam {
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

	/** A highlight keyword in Regular Expression mode: a pattern the reader
	 wrote, matched against text a stranger sent.

	 That pairing is the one the cap is for -- the cost of a pathological
	 pattern grows with the input, and only the reader's patterns are
	 unbounded in shape. The cap is far past any real message and far short of
	 anything that could stall a render. */
	private func ranges(ofRegularExpression pattern: String) -> [NSRange] {
		guard let expression = TranscriptHighlightExpressions.shared.expression(for: pattern) else { return [] }
		return ranges(
			of: expression,
			matchedLength: min((body as NSString).length, TranscriptHighlightExpressions.maximumMatchedLength)
		)
	}

	private func ranges(of expression: NSRegularExpression, matchedLength: Int) -> [NSRange] {
		expression.matches(
			in: body,
			range: NSRange(location: 0, length: matchedLength)
		).map(\.range).filter { $0.length > 0 }
	}

	private func isSurroundedByNonAlphanumerics(_ range: NSRange) -> Bool {
		let source = body as NSString
		guard range.length > 0, range.location < source.length, NSMaxRange(range) <= source.length else { return false }
		/** `Unicode.Scalar.Properties` carries the current tables. The hand-written
		 range tables this replaced were generated around 2007 and stopped at
		 U+1D7CB, so every script added since was classified as non-alphabetic. */
		func isAlphanumeric(_ character: UniChar) -> Bool {
			character >= 48 && character <= 57
				|| Unicode.Scalar(character)?.properties.isAlphabetic == true
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

	private func result(from attributedBody: NSMutableAttributedString) -> TranscriptBody {
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
				policy.linkSchemes.permits(link: link.stringValue),
				let url = URL(string: link.stringValue)
			{
				.link(url)
			} else if let channel = attributes[RendererFormatting.channelName] as? String {
				.channel(channel)
			} else if let nickname = attributes[RendererFormatting.conversationTracking] as? String {
				.nickname(nickname)
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

	private static func nativeColor(_ value: Any?) -> TranscriptRunColor? {
		if let index = value as? NSNumber {
			return .palette(index.intValue)
		}
		guard let color = value as? NSColor, let components = TranscriptThemeColor(color) else { return nil }
		return .rgb(components)
	}
}

/// A complete member nickname in the message, with explicit address markers
/// kept separate from the bare names used to detect highlight spam.
private nonisolated struct TranscriptMemberReference {
	let nickname: String
	let range: NSRange
	let isExplicitMention: Bool

	static func locate(in text: String, members: RenderedMemberDirectory) -> [Self] {
		let scalars = Array(text.unicodeScalars)
		var references: [Self] = []
		var index = 0
		var utf16Offset = 0
		while index < scalars.count {
			guard isNicknameCharacter(scalars[index]) else {
				utf16Offset += scalars[index].value > 0xFFFF ? 2 : 1
				index += 1
				continue
			}
			let start = index
			let rangeStart = utf16Offset
			while index < scalars.count, isNicknameCharacter(scalars[index]) {
				utf16Offset += scalars[index].value > 0xFFFF ? 2 : 1
				index += 1
			}
			let spelling = String(String.UnicodeScalarView(scalars[start ..< index]))
			guard let member = members.member(named: spelling) else { continue }
			references.append(Self(
				nickname: member.nickname,
				range: NSRange(location: rangeStart, length: utf16Offset - rangeStart),
				isExplicitMention: hasAddressMarker(in: scalars, start: start, end: index)
			))
		}
		return references
	}

	private static func hasAddressMarker(in scalars: [Unicode.Scalar], start: Int, end: Int) -> Bool {
		let previous = start > 0 ? scalars[start - 1] : nil
		let next = end < scalars.count ? scalars[end] : nil
		if previous == "@" {
			// Reject email addresses and repeated markers, including an embedded
			// address with a trailing colon. The marker must begin its own word.
			guard next != "@" else { return false }
			return start == 1 || (scalars[start - 2] != "@" && !isNicknameCharacter(scalars[start - 2]))
		}
		return next == ":"
	}

	private static func isNicknameCharacter(_ scalar: Unicode.Scalar) -> Bool {
		// Keep IRC's nickname punctuation together so @get cannot target the
		// first part of get_more or get-away. Combining marks stay attached
		// before the directory applies the server's Unicode normalization.
		CharacterSet.alphanumerics.contains(scalar)
			|| CharacterSet.nonBaseCharacters.contains(scalar)
			|| "-[]\\`_^{}|~".unicodeScalars.contains(scalar)
	}
}

extension TranscriptRenderer {
	nonisolated static func renderNativeBody( // nonisolated: pure
		_ body: String,
		withAttributes configuration: TranscriptRenderOptions,
		members: RenderedMemberDirectory
	) -> TranscriptBody {
		guard body.isEmpty == false else { return TranscriptBody() }
		var renderer = TranscriptRenderer(body: body, configuration: configuration, members: members)
		renderer.filterUnicodeSpam()
		let attributedBody = renderer.parseFormatting()
		renderer.annotateLinks(in: attributedBody)
		renderer.annotateHighlight(in: attributedBody)
		renderer.annotateChannels(in: attributedBody)
		renderer.annotateMembers(in: attributedBody)

		return renderer.result(from: attributedBody)
	}
}

/** The setting values the renderer branches on, read once on the main actor
 and carried into the render with the line.

 Reading them from inside the renderer made a render a function of hidden global
 state: the same body and the same options could produce two different results
 and nothing in the signature said so. */
nonisolated struct TranscriptTextRules: Sendable {
	var filtersUnicodeTextSpam = false
	var highlightMatchingMethod = NicknameHighlightMatchMode.exact
	var detectsHighlightSpam = true
	var linkSchemes = LinkSchemeRules()

	init(
		filtersUnicodeTextSpam: Bool = false,
		highlightMatchingMethod: NicknameHighlightMatchMode = .exact,
		detectsHighlightSpam: Bool = true,
		linkSchemes: LinkSchemeRules = LinkSchemeRules()
	) {
		self.filtersUnicodeTextSpam = filtersUnicodeTextSpam
		self.highlightMatchingMethod = highlightMatchingMethod
		self.detectsHighlightSpam = detectsHighlightSpam
		self.linkSchemes = linkSchemes
	}

	/// The policy the reader's settings describe right now.
	@MainActor static func current() -> TranscriptTextRules {
		TranscriptTextRules(
			filtersUnicodeTextSpam: SettingsKeys.Messages.filterUnicodeTextSpam.value,
			highlightMatchingMethod: SettingsKeys.Highlights.matchingMethod.value,
			detectsHighlightSpam: SettingsKeys.Messages.detectHighlightSpam.value,
			linkSchemes: .current()
		)
	}
}

nonisolated struct TranscriptRenderOptions: Sendable {
	var renderLinks = false
	var lineType = ChatLineKind.undefined
	var memberType = ChatLineMemberKind.normal
	var highlightKeywords: [String] = []
	var excludedKeywords: [String] = []
	/// The setting facts the render needs, taken on the main actor.
	var textPolicy = TranscriptTextRules()
	/// The server's casemapping for member nickname references.
	var caseMapping = ISupportCaseMapping.rfc1459
}
