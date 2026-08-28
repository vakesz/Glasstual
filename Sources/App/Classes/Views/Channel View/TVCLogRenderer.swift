/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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
import Mustache
import OSLog

public typealias TVCLogRendererConfigurationAttribute = String
public typealias TVCLogRendererResultsAttribute = String
public typealias TVCLogRenderer = LogRenderer

public extension String {
	static let renderLinksAttribute = LogRendererConfigurationKey.renderLinks.rawValue
	static let lineTypeAttribute = LogRendererConfigurationKey.lineType.rawValue
	static let memberTypeAttribute = LogRendererConfigurationKey.memberType.rawValue
	static let highlightKeywordsAttribute = LogRendererConfigurationKey.highlightKeywords.rawValue
	static let excludedKeywordsAttribute = LogRendererConfigurationKey.excludedKeywords.rawValue
	static let doNotEscapeBodyAttribute = LogRendererConfigurationKey.doNotEscapeBody.rawValue
	static let attributedStringPreferredFontAttribute = LogRendererConfigurationKey.preferredFont.rawValue
	static let attributedStringPreferredFontColorAttribute = LogRendererConfigurationKey.preferredFontColor.rawValue

	static let listOfLinksInBodyAttribute = LogRendererResultKey.links.rawValue
	static let listOfLinksMappedInBodyAttribute = LogRendererResultKey.mappedLinks.rawValue
	static let keywordMatchFoundAttribute = LogRendererResultKey.keywordMatchFound.rawValue
	static let listOfUsersFoundAttribute = LogRendererResultKey.users.rawValue
	static let originalBodyWithoutEffectsAttribute = LogRendererResultKey.bodyWithoutEffects.rawValue
}

private let rendererLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogRenderer"
)

/** Patterns that are the same for every rendered line.

 They used to be recompiled per line — `findAllChannelNames()` runs on every
 private message — and an invalid pattern makes `replacingOccurrences(options:
 .regularExpression)` silently return its input, so a broken filter would look
 exactly like a working one.

 These stay `NSRegularExpression` rather than Swift `Regex` literals: the
 combining-marks pattern names a Unicode *block*, which the literal parser
 rejects ("Unicode block property is not currently supported"), and `Regex`
 matches grapheme clusters by default, which would stop the combining marks
 from being seen individually at all. */
private enum RendererPatterns {
	/// Three or more stacked combining marks — "Zalgo" text.
	static let combiningMarks = compile("[\\p{InCombining_Diacritical_Marks}]{3,}")

	/// A channel name mentioned inside a private message or notice.
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

private enum RendererFormatting {
	struct Toggle {
		let attribute: NSAttributedString.Key
		let activeToken: ThemeTemplateAttribute
		let openedToken: ThemeTemplateAttribute
		let closedAtStartToken: ThemeTemplateAttribute
		let closedAtEndToken: ThemeTemplateAttribute
	}

	struct ColorTokens {
		let color: ThemeTemplateAttribute
		let isSet: ThemeTemplateAttribute
	}

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

	static let toggles = [
		Toggle(
			attribute: bold,
			activeToken: .fragmentIsBold,
			openedToken: .fragmentIsBoldOpened,
			closedAtStartToken: .fragmentIsBoldClosedAtStart,
			closedAtEndToken: .fragmentIsBoldClosedAtEnd
		),
		Toggle(
			attribute: italic,
			activeToken: .fragmentIsItalicized,
			openedToken: .fragmentIsItalicizedOpened,
			closedAtStartToken: .fragmentIsItalicizedClosedAtStart,
			closedAtEndToken: .fragmentIsItalicizedClosedAtEnd
		),
		Toggle(
			attribute: monospace,
			activeToken: .fragmentIsMonospace,
			openedToken: .fragmentIsMonospaceOpened,
			closedAtStartToken: .fragmentIsMonospaceClosedAtStart,
			closedAtEndToken: .fragmentIsMonospaceClosedAtEnd
		),
		Toggle(
			attribute: strikethrough,
			activeToken: .fragmentIsStruckthrough,
			openedToken: .fragmentIsStruckthroughOpened,
			closedAtStartToken: .fragmentIsStruckthroughClosedAtStart,
			closedAtEndToken: .fragmentIsStruckthroughClosedAtEnd
		),
		Toggle(
			attribute: underline,
			activeToken: .fragmentIsUnderlined,
			openedToken: .fragmentIsUnderlinedOpened,
			closedAtStartToken: .fragmentIsUnderlinedClosedAtStart,
			closedAtEndToken: .fragmentIsUnderlinedClosedAtEnd
		),
	]

	static let foregroundColorTokens = ColorTokens(
		color: .fragmentForegroundColor,
		isSet: .fragmentForegroundColorIsSet
	)
	static let backgroundColorTokens = ColorTokens(
		color: .fragmentBackgroundColor,
		isSet: .fragmentBackgroundColorIsSet
	)
}

@objc(TVCLogRenderer)
public final class LogRenderer: NSObject {
	private var body = ""
	private var bodyWithAttributes = NSMutableAttributedString()
	private var openAttributes: [NSAttributedString.Key: Any] = [:]
	private var rendererAttributes = LogRendererConfiguration()
	private var output = LogRendererResults()
	private weak var viewController: LogController?
	private var lineType = TVCLogLineType.undefined
	private var memberType = TVCLogLineMemberType.normal
	private var escapeBody = true

	private var isRenderingPrivateMessage: Bool {
		lineType == .privateMessage || lineType == .action
	}

	private var isRenderingPrivateMessageOrNotice: Bool {
		isRenderingPrivateMessage || lineType == .notice
	}

	private func buildEffectsDictionary() {
		let original = body as NSString
		let inputLength = original.length
		var characters = [UniChar](repeating: 0, count: inputLength)
		if inputLength > 0 {
			original.getCharacters(&characters, range: NSRange(location: 0, length: inputLength))
		}

		let attributedBody = NSMutableAttributedString(string: body)
		attributedBody.beginEditing()
		var removedCount = 0
		var index = 0
		while index < inputLength {
			let character = characters[index]
			let position = index - removedCount
			guard character < 0x20 else {
				index += 1
				continue
			}

			func toggle(_ key: NSAttributedString.Key) {
				if position > 0, attributedBody.attribute(key, at: position, effectiveRange: nil) != nil {
					attributedBody.removeAttribute(
						key,
						range: NSRange(location: position, length: attributedBody.length - position)
					)
				} else {
					attributedBody.addAttribute(
						key,
						value: true,
						range: NSRange(location: position, length: attributedBody.length - position)
					)
				}
				attributedBody.deleteCharacters(in: NSRange(location: position, length: 1))
				removedCount += 1
			}

			switch character {
			case UniChar(IRCTextFormatterControlCharacter.bold):
				toggle(RendererFormatting.bold)
			case UniChar(IRCTextFormatterControlCharacter.italic),
			     UniChar(IRCTextFormatterControlCharacter.legacyItalic):
				toggle(RendererFormatting.italic)
			case UniChar(IRCTextFormatterControlCharacter.monospace):
				toggle(RendererFormatting.monospace)
			case UniChar(IRCTextFormatterControlCharacter.strikethrough):
				toggle(RendererFormatting.strikethrough)
			case UniChar(IRCTextFormatterControlCharacter.underline):
				toggle(RendererFormatting.underline)
			case UniChar(IRCTextFormatterControlCharacter.colorDigit),
			     UniChar(IRCTextFormatterControlCharacter.colorHex):
				var foreground: AnyObject?
				var background: AnyObject?
				let consumed = Int((attributedBody.string as NSString).colorComponents(
					ofCharacter: character,
					startingAt: UInt(position),
					foregroundColor: &foreground,
					backgroundColor: &background
				))
				applyColor(foreground, key: RendererFormatting.foregroundColor, at: position, to: attributedBody)
				if let background {
					applyColor(background, key: RendererFormatting.backgroundColor, at: position, to: attributedBody)
				} else if foreground == nil, position > 0 {
					removeAttribute(RendererFormatting.backgroundColor, at: position, from: attributedBody)
				}
				let safeConsumed = max(consumed, 1)
				attributedBody.deleteCharacters(in: NSRange(location: position, length: safeConsumed))
				removedCount += safeConsumed
				index += safeConsumed - 1
			case UniChar(IRCTextFormatterControlCharacter.terminator):
				attributedBody.setAttributes(
					[:],
					range: NSRange(location: position, length: attributedBody.length - position)
				)
				attributedBody.deleteCharacters(in: NSRange(location: position, length: 1))
				removedCount += 1
			default:
				break
			}
			index += 1
		}
		attributedBody.endEditing()
		body = attributedBody.string
		bodyWithAttributes = attributedBody
		output[.bodyWithoutEffects] = body
	}

	private func applyColor(
		_ color: AnyObject?,
		key: NSAttributedString.Key,
		at position: Int,
		to attributedBody: NSMutableAttributedString
	) {
		if let color {
			attributedBody.addAttribute(
				key,
				value: color,
				range: NSRange(location: position, length: attributedBody.length - position)
			)
		} else if position > 0 {
			removeAttribute(key, at: position, from: attributedBody)
		}
	}

	private func removeAttribute(
		_ key: NSAttributedString.Key,
		at position: Int,
		from attributedBody: NSMutableAttributedString
	) {
		guard attributedBody.attribute(key, at: position, effectiveRange: nil) != nil else {
			return
		}
		attributedBody.removeAttribute(
			key,
			range: NSRange(location: position, length: attributedBody.length - position)
		)
	}

	private func stripDangerousUnicodeCharacters() {
		guard TextualPreferences.automaticallyFilterUnicodeTextSpam() else {
			return
		}
		let filteredTypes: Set<TVCLogLineType> = [
			.action, .ctcp, .ctcpQuery, .ctcpReply, .dccFileTransfer, .notice, .privateMessage, .topic,
		]
		guard filteredTypes.contains(lineType) else {
			return
		}
		body = Self.strippingDangerousUnicodeCharacters(body)
	}

	/** Collapses runs of three or more stacked combining marks — "Zalgo" text,
	 which paints over neighbouring lines — into one replacement character.

	 Returns `text` unchanged if the pattern failed to compile, which is why
	 `RendererPatterns` logs that case: a silent no-op filter looks exactly
	 like a working one. */
	static func strippingDangerousUnicodeCharacters(_ text: String) -> String {
		guard let expression = RendererPatterns.combiningMarks else {
			return text
		}
		return expression.stringByReplacingMatches(
			in: text,
			range: NSRange(location: 0, length: (text as NSString).length),
			withTemplate: unicodeReplacementCharacter
		)
	}

	private func buildListOfLinks() {
		guard boolAttribute(.renderLinks) else {
			return
		}
		let links = LinkParser.locateLinks(in: body)
		var mapped: [String: String] = [:]
		for link in links {
			bodyWithAttributes.addAttribute(RendererFormatting.url, value: link, range: link.range)
			mapped[link.stringValue, default: link.uniqueIdentifier] = mapped[link.stringValue] ?? link.uniqueIdentifier
		}
		output[.links] = links
		output[.mappedLinks] = mapped
	}

	private func matchKeywords() {
		guard isRenderingPrivateMessage, memberType == .normal else {
			return
		}
		let highlighted = rendererAttributes.value(for: .highlightKeywords, as: [String].self) ?? []
		guard highlighted.isEmpty == false else {
			output[.keywordMatchFound] = false
			return
		}
		let excluded = rendererAttributes.value(for: .excludedKeywords, as: [String].self) ?? []
		let excludedRanges = excluded.flatMap { ranges(of: $0, options: .caseInsensitive) }
		let matchMethod = TextualPreferences.highlightMatchingMethod()
		var found = false
		for keyword in highlighted where found == false {
			let matches: [NSRange] = if matchMethod == .regularExpression {
				Array(ranges(ofRegularExpression: keyword).prefix(1))
			} else {
				ranges(of: keyword, options: .caseInsensitive)
			}
			for range in matches {
				guard excludedRanges.allSatisfy({ NSIntersectionRange(range, $0).length == 0 }) else {
					continue
				}
				if matchMethod == .exact, isSurroundedByNonAlphanumerics(range) == false {
					continue
				}
				guard bodyWithAttributes
					.attribute(RendererFormatting.url, at: range.location, effectiveRange: nil) == nil
				else {
					continue
				}
				bodyWithAttributes.addAttribute(RendererFormatting.keywordHighlight, value: true, range: range)
				found = true
				break
			}
		}
		output[.keywordMatchFound] = found
	}

	private func findAllChannelNames() {
		guard isRenderingPrivateMessageOrNotice else {
			return
		}
		guard let expression = RendererPatterns.channelName else {
			return
		}
		for range in ranges(of: expression) {
			guard isSurroundedByNonAlphanumerics(range),
			      bodyWithAttributes.attribute(RendererFormatting.url, at: range.location, effectiveRange: nil) == nil
			else {
				continue
			}
			bodyWithAttributes.addAttribute(RendererFormatting.channelName, value: true, range: range)
		}
	}

	private func scanBodyForChannelMembers() {
		guard isRenderingPrivateMessage else {
			return
		}
		guard body.isEmpty == false else {
			output[.users] = Set<ChannelUser>()
			return
		}
		guard let users = viewController?.associatedChannel?.memberList else {
			output[.users] = Set<ChannelUser>()
			return
		}
		var foundUsers = Set<ChannelUser>()
		var nicknameCount = 0
		var nicknameLength = 0
		for user in users {
			for range in ranges(of: user.user.nickname, options: .caseInsensitive) {
				guard isSurroundedByNonAlphanumerics(range),
				      bodyWithAttributes
				      .attribute(RendererFormatting.url, at: range.location, effectiveRange: nil) == nil
				else {
					continue
				}
				bodyWithAttributes.addAttribute(RendererFormatting.conversationTracking, value: true, range: range)
				foundUsers.insert(user)
				if bodyWithAttributes.attribute(
					RendererFormatting.keywordHighlight,
					at: range.location,
					effectiveRange: nil
				) == nil {
					nicknameCount += 1
					nicknameLength += range.length
				}
			}
		}
		if TextualPreferences.automaticallyDetectHighlightSpam() {
			let nicknamePercent = Double(nicknameLength) / Double((body as NSString).length) * 100
			if (nicknamePercent > 75 && nicknameCount > 10) || (nicknamePercent > 50 && nicknameCount > 20) {
				output[.keywordMatchFound] = false
			}
		}
		output[.users] = foundUsers
	}

	private func ranges(of searchString: String, options: NSString.CompareOptions) -> [NSRange] {
		guard searchString.isEmpty == false else {
			return []
		}
		let source = body as NSString
		var searchRange = NSRange(location: 0, length: source.length)
		var result: [NSRange] = []
		while searchRange.length > 0 {
			let range = source.range(of: searchString, options: options, range: searchRange)
			guard range.location != NSNotFound else {
				break
			}
			result.append(range)
			let next = NSMaxRange(range)
			searchRange = NSRange(location: next, length: source.length - next)
		}
		return result
	}

	/** Schemes that must never reach an `href`, whatever the link parser or the
	 user's `permittedSchemes` defaults say. `javascript:` and `data:` execute
	 in the log view, which holds the native `app` bridge. */
	private static let refusedAnchorSchemes: Set<String> = [
		"javascript", "data", "vbscript", "blob", "filesystem", "about",
	]

	/** Whether a parsed link may be rendered as an anchor.

	 `LinkParser` already refuses unknown schemes when the text carries one,
	 but its permitted set is user-configurable (`permittedSchemesAny` opens it
	 to everything), so the decision is repeated here — at the boundary where
	 the value stops being a parse result and becomes an attribute of the
	 rendered document. A refused link is rendered as escaped plain text. */
	static func isRenderableAnchorLocation(_ location: String) -> Bool {
		guard let scheme = anchorScheme(location) else {
			/* Without a scheme the href resolves against the theme's file:// base. */
			rendererLogger.error("Refusing to render an anchor without a URL scheme")
			return false
		}
		guard refusedAnchorSchemes.contains(scheme) == false, LinkParser.isPermittedScheme(scheme) else {
			rendererLogger.error("Refusing to render anchor with scheme '\(scheme, privacy: .public)'")
			return false
		}
		return true
	}

	/// The scheme of `location`, lowercased, if it is syntactically a URL scheme.
	private static func anchorScheme(_ location: String) -> String? {
		guard let colon = location.firstIndex(of: ":") else {
			return nil
		}
		let scheme = location[location.startIndex ..< colon]
		guard let first = scheme.first, first.isLetter else {
			return nil
		}
		let isSchemeCharacter = { (character: Character) in
			character.isLetter || character.isNumber || character == "+" || character == "-" || character == "."
		}
		guard scheme.allSatisfy(isSchemeCharacter) else {
			return nil
		}
		return scheme.lowercased()
	}

	private func ranges(ofRegularExpression pattern: String) -> [NSRange] {
		/* The pattern is a user-configured highlight keyword, so it cannot be
		 cached alongside the fixed patterns in `RendererPatterns`. */
		guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
			return []
		}
		return ranges(of: expression)
	}

	private func ranges(of expression: NSRegularExpression) -> [NSRange] {
		let range = NSRange(location: 0, length: (body as NSString).length)
		return expression.matches(in: body, range: range).map(\.range)
	}

	private func isSurroundedByNonAlphanumerics(_ range: NSRange) -> Bool {
		let source = body as NSString
		guard range.length > 0, range.location < source.length, NSMaxRange(range) <= source.length else {
			return false
		}
		func isAlphanumeric(_ character: UniChar) -> Bool {
			character >= 48 && character <= 57 || UnicodeHelper.isAlphabeticalCodePoint(Int(character))
		}
		if isAlphanumeric(source.character(at: range.location)), range.location > 0,
		   isAlphanumeric(source.character(at: range.location - 1))
		{
			return false
		}
		let right = NSMaxRange(range)
		if isAlphanumeric(source.character(at: right - 1)), right < source.length,
		   isAlphanumeric(source.character(at: right))
		{
			return false
		}
		return true
	}

	private func renderHTML() -> String {
		var result = ""
		let source = bodyWithAttributes.string
		let length = bodyWithAttributes.length
		bodyWithAttributes.enumerateAttributes(
			in: NSRange(location: 0, length: length),
			options: []
		) { [self] attributes, range, _ in
			if let fragment = renderHTMLFragment(
				source,
				attributes: attributes,
				range: range,
				isFirst: range.location == 0,
				isLast: NSMaxRange(range) == length
			) {
				result += fragment
			}
		}
		return result
	}

	private func renderHTMLFragment(
		_ source: String,
		attributes: [NSAttributedString.Key: Any],
		range: NSRange,
		isFirst: Bool,
		isLast: Bool
	) -> String? {
		let sourceNSString = source as NSString
		let fragment = sourceNSString.substring(with: range)
		var tokens: ThemeTemplateAttributes = [:]
		var html: String?

		if let link = attributes[RendererFormatting.url] as? LinkParserResult,
		   Self.isRenderableAnchorLocation(link.stringValue)
		{
			if viewController?.inlineMediaEnabledForView == true,
			   let mapped = output.value(for: .mappedLinks, as: [String: String].self),
			   let identifier = mapped[link.stringValue]
			{
				tokens[.anchorInlineMediaAvailable] = true
				tokens[.anchorInlineMediaUniqueID] = identifier
			}
			tokens[.anchorLocation] = link.stringValue
			tokens[.anchorTitle] = Self.escapeString(fragment)
			html = Self.renderTemplateNamed(.renderedStandardAnchorLinkResource, attributes: tokens)
		} else if attributes[RendererFormatting.channelName] != nil {
			tokens[.channelName] = Self.escapeString(fragment)
			html = Self.renderTemplateNamed(.renderedChannelNameLinkResource, attributes: tokens)
		} else if attributes[RendererFormatting.conversationTracking] != nil {
			if TextualPreferences.disableNicknameColorHashing() {
				tokens[.inlineNicknameMatchFound] = false
			} else if let member = viewController?.associatedChannel?.findMember(fragment) {
				let nickname = member.user.nickname
				if nickname.count > 1 {
					var modeSymbol = ""
					if TextualPreferences.conversationTrackingIncludesUserModeSymbol() {
						let mark = member.mark
						if range.location == 0 || sourceNSString.substring(with: NSRange(
							location: range.location - 1,
							length: 1
						)) != mark {
							modeSymbol = mark
						}
					}
					tokens[.inlineNicknameMatchFound] = true
					tokens[.inlineNicknameColorStyle] = UserNicknameColorStyleGenerator
						.nicknameColorStyle(for: nickname)
					tokens[.inlineNicknameUserModeSymbol] = modeSymbol
				}
			}
			html = Self.escapeString(fragment)
		}

		tokens[.messageFragmentEscaped] = escapeBody
		if html == nil {
			html = escapeBody ? Self.escapeString(fragment) : fragment
		}

		for toggle in RendererFormatting.toggles {
			if attributes[toggle.attribute] != nil {
				tokens[toggle.activeToken] = true
				if openAttributes[toggle.attribute] == nil {
					openAttributes[toggle.attribute] = true
					tokens[toggle.openedToken] = true
				}
				if isLast {
					tokens[toggle.closedAtEndToken] = true
				}
			} else if openAttributes.removeValue(forKey: toggle.attribute) != nil {
				tokens[toggle.closedAtStartToken] = true
			}
		}

		applyHTMLColors(attributes, tokens: &tokens, isFirst: isFirst, isLast: isLast)
		if escapeBody, var htmlValue = html {
			if htmlValue.hasPrefix(" ") {
				htmlValue.replaceSubrange(htmlValue.startIndex ... htmlValue.startIndex, with: "&nbsp;")
			}
			if htmlValue.hasSuffix(" ") {
				let lastIndex = htmlValue.index(before: htmlValue.endIndex)
				htmlValue.replaceSubrange(lastIndex ... lastIndex, with: "&nbsp;")
			}
			html = htmlValue
		}
		tokens[.messageFragment] = html ?? ""
		return Self.renderTemplateNamed(.formattedMessageFragment, attributes: tokens)
	}

	private func applyHTMLColors(
		_ attributes: [NSAttributedString.Key: Any],
		tokens: inout ThemeTemplateAttributes,
		isFirst: Bool,
		isLast: Bool
	) {
		let foregroundNew = attributes[RendererFormatting.foregroundColor]
		let backgroundNew = attributes[RendererFormatting.backgroundColor]
		let foregroundOld = openAttributes[RendererFormatting.foregroundColor]
		let backgroundOld = openAttributes[RendererFormatting.backgroundColor]
		var foreground: String?
		var background: String?
		var setNewColors = true
		if foregroundOld != nil || backgroundOld != nil {
			if valuesEqual(foregroundNew, foregroundOld), valuesEqual(backgroundNew, backgroundOld) {
				setNewColors = false
			} else {
				tokens[.fragmentTextColorClosedAtStart] = isFirst == false
				tokens[.fragmentTextColorClosedAtEnd] = isLast
			}
			if foregroundOld != nil, foregroundNew == nil {
				openAttributes.removeValue(forKey: RendererFormatting.foregroundColor)
			}
			if backgroundOld != nil, backgroundNew == nil {
				openAttributes.removeValue(forKey: RendererFormatting.backgroundColor)
			}
		}

		func apply(
			_ value: Any?,
			key: NSAttributedString.Key,
			colorTokens: RendererFormatting.ColorTokens
		) -> String? {
			guard setNewColors, let value else {
				return nil
			}
			openAttributes[key] = value
			guard let mapped = Self.stringValue(forColor: value) else {
				return nil
			}
			tokens[.fragmentTextColorOpened] = true
			tokens[colorTokens.color] = mapped.value
			tokens[colorTokens.isSet] = true
			tokens[.fragmentTextColorUsesStyleTag] = mapped.usesStyleTag
			tokens[.fragmentTextColorIsSet] = true
			return mapped.value
		}
		foreground = apply(
			foregroundNew,
			key: RendererFormatting.foregroundColor,
			colorTokens: RendererFormatting.foregroundColorTokens
		)
		if let foreground {
			tokens[.fragmentTextColor] = foreground
		}
		background = apply(
			backgroundNew,
			key: RendererFormatting.backgroundColor,
			colorTokens: RendererFormatting.backgroundColorTokens
		)
		tokens[.fragmentIsSpoiler] = isRenderingPrivateMessageOrNotice && setNewColors && foreground != nil &&
			foreground == background
	}

	private func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
		switch (lhs, rhs) {
		case (nil, nil): true
		case let (left as NSObject, right as NSObject): left == right
		default: false
		}
	}

	private func renderAttributedBody() -> NSAttributedString {
		let result = NSMutableAttributedString(attributedString: bodyWithAttributes)
		bodyWithAttributes.enumerateAttributes(
			in: NSRange(location: 0, length: bodyWithAttributes.length),
			options: []
		) { [self] attributes, range, _ in
			result.addAttributes(appKitAttributes(from: attributes), range: range)
		}
		return result
	}

	private func appKitAttributes(from attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
		var result: [NSAttributedString.Key: Any] = [:]
		let defaultFont = rendererAttributes.value(for: .preferredFont, as: NSFont.self)
		let defaultColor = rendererAttributes.value(for: .preferredFontColor, as: NSColor.self)
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
			let converted = NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
			font = converted.textual_fontTraitIsSet(.italicFontMask) ? converted : italicFallback(for: converted)
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
			result[.foregroundColor] = Self.mapColor(foreground)
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.foregroundColorAttributeName.rawValue)] =
				foreground
		} else if let defaultColor {
			result[.foregroundColor] = defaultColor
		}
		if let background = attributes[RendererFormatting.backgroundColor] {
			result[.backgroundColor] = Self.mapColor(background)
			result[NSAttributedString.Key(IRCTextFormatterAttributeName.backgroundColorAttributeName.rawValue)] =
				background
		}
		return result.compactMapValues { $0 }
	}

	private func italicFallback(for font: NSFont) -> NSFont {
		let fontTransform = AffineTransform(scaleByX: font.pointSize, byY: font.pointSize)
		let shear = CGFloat(-tan(-14 * Double.pi / 180))
		let italicTransform = AffineTransform(m11: 1, m12: 0, m21: shear, m22: 1, tX: 0, tY: 0)
		var transform = fontTransform
		transform.append(italicTransform)
		return NSFont(descriptor: font.fontDescriptor, textTransform: transform) ?? font
	}

	private func boolAttribute(_ key: LogRendererConfigurationKey) -> Bool {
		(rendererAttributes[key] as? NSNumber)?.boolValue ?? (rendererAttributes[key] as? Bool ?? false)
	}
}

public extension LogRenderer {
	@objc(renderBody:forViewController:withAttributes:resultInfo:)
	static func renderBody(
		_ body: String,
		forViewController legacyViewController: TVCLogController,
		withAttributes input: [String: Any],
		resultInfo: AutoreleasingUnsafeMutablePointer<NSDictionary?>?
	) -> String {
		guard body.isEmpty == false else {
			return ""
		}
		let configuration = LogRendererConfiguration(rawValues: input)
		let renderer = LogRenderer()
		let controller = legacyViewController
		renderer
			.lineType = TVCLogLineType(
				rawValue: configuration.value(for: .lineType, as: UInt.self) ?? 0
			) ?? .undefined
		renderer
			.memberType = TVCLogLineMemberType(
				rawValue: configuration.value(for: .memberType, as: UInt.self) ?? 0
			) ?? .normal
		renderer.body = PluginDispatcher.willRenderMessage(
			body,
			forViewController: controller,
			lineType: renderer.lineType,
			memberType: renderer.memberType
		)
		renderer.escapeBody = (configuration[.doNotEscapeBody] as? NSNumber)?.boolValue != true
		renderer.rendererAttributes = configuration
		renderer.viewController = controller
		renderer.stripDangerousUnicodeCharacters()
		renderer.buildEffectsDictionary()
		renderer.buildListOfLinks()
		renderer.matchKeywords()
		renderer.findAllChannelNames()
		renderer.scanBodyForChannelMembers()
		resultInfo?.pointee = renderer.output.rawValues as NSDictionary
		return renderer.renderHTML()
	}

	@objc(renderBodyAsAttributedString:withAttributes:)
	static func renderBody(
		asAttributedString body: String,
		withAttributes input: [String: Any]
	) -> NSAttributedString {
		guard body.isEmpty == false else {
			return NSAttributedString(string: "")
		}
		let configuration = LogRendererConfiguration(rawValues: input)
		precondition(configuration[.preferredFont] != nil)
		let renderer = LogRenderer()
		renderer.body = body
		renderer
			.lineType = TVCLogLineType(
				rawValue: configuration.value(for: .lineType, as: UInt.self) ?? 0
			) ?? .undefined
		renderer
			.memberType = TVCLogLineMemberType(
				rawValue: configuration.value(for: .memberType, as: UInt.self) ?? 0
			) ?? .normal
		renderer.rendererAttributes = configuration
		renderer.stripDangerousUnicodeCharacters()
		renderer.buildEffectsDictionary()
		return renderer.renderAttributedBody()
	}

	@objc(renderTemplateNamed:)
	static func renderTemplateNamed(_ name: String) -> String? {
		renderTemplateNamed(name, attributes: nil)
	}

	@objc(renderTemplateNamed:attributes:)
	static func renderTemplateNamed(_ name: String, attributes: [String: Any]?) -> String? {
		guard let template = SharedApplication.sharedThemeController().theme?.template(withName: name) else {
			return nil
		}
		return renderTemplate(template, attributes: attributes)
	}

	internal static func renderTemplateNamed(
		_ name: ThemeTemplateName,
		attributes: ThemeTemplateAttributes = [:]
	) -> String? {
		guard let template = SharedApplication.sharedThemeController().theme?.template(withName: name.rawValue) else {
			return nil
		}
		return renderTemplate(template, attributes: attributes)
	}

	static func renderTemplate(_ template: Template) -> String? {
		renderTemplate(template, attributes: nil)
	}

	static func renderTemplate(_ template: Template, attributes: [String: Any]?) -> String? {
		guard let rendered = try? template.render(attributes) else {
			return nil
		}
		return rendered.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
	}

	internal static func renderTemplate(_ template: Template, attributes: ThemeTemplateAttributes) -> String? {
		renderTemplate(template, attributes: attributes.rawValues)
	}

	@objc(escapeHTML:)
	static func escapeHTML(_ html: String) -> String {
		(html as NSString).gtmStringByEscapingForHTML ?? ""
	}

	private static func escapeString(_ string: String) -> String {
		escapeHTML(string)
			.replacingOccurrences(of: "\t", with: "&nbsp;&nbsp;&nbsp;&nbsp;")
			.replacingOccurrences(of: "  ", with: "&nbsp;&nbsp;")
	}

	private static func stringValue(forColor color: Any) -> (value: String, usesStyleTag: Bool)? {
		if let color = color as? NSColor {
			return (color.textualHexadecimalValue, true)
		}
		if let color = color as? NSNumber {
			return (color.stringValue, false)
		}
		return nil
	}

	@objc(mapColor:)
	static func mapColor(_ color: Any) -> NSColor? {
		if let color = color as? NSColor {
			return color
		}
		if let color = color as? NSNumber {
			return mapColorCode(color.uintValue)
		}
		return nil
	}

	@objc(mapColorCode:)
	static func mapColorCode(_ colorCode: UInt) -> NSColor {
		precondition(colorCode <= IRCTextFormatterColor.maximumPaletteIndex)
		return NSColor.formatterColors[Int(colorCode)]
	}
}
