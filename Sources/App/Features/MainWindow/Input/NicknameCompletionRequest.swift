// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

enum CompletionKind: Sendable {
	case nickname
	case channelName
	case command
}

struct CompletionRequest {
	let kind: CompletionKind
	let searchPattern: String
	let prefix: String
	let isAtStart: Bool
	let searchRange: NSRange
	var suffixRange: NSRange
	let originalSuffix: String

	init?(textValue: String, selection: NSRange) {
		guard selection.location != NSNotFound else {
			return nil
		}

		let text = textValue as NSString
		var searchStart = 0

		if selection.location > 0 {
			for index in stride(from: selection.location - 1, through: 0, by: -1) {
				let character = text.character(at: index)

				if Self.isWordDelimiter(character) {
					searchStart = index + 1
					break
				}
			}
		}

		let range = NSRange(location: searchStart, length: selection.location - searchStart)
		var pattern = text.substring(with: range)
		let atStart = searchStart == 0
		let resolvedKind: CompletionKind
		let resolvedPrefix: String

		if atStart, pattern.hasPrefix("/") {
			resolvedKind = .command
			resolvedPrefix = "/"
			pattern.removeFirst()
		} else if pattern.hasPrefix("@") {
			resolvedKind = .nickname
			resolvedPrefix = "@"
			pattern.removeFirst()
		} else if pattern.hasPrefix("#") {
			resolvedKind = .channelName
			resolvedPrefix = ""
		} else {
			resolvedKind = .nickname
			resolvedPrefix = ""
		}

		let completionSuffixRange = Self.completionSuffixRange(
			in: text,
			selection: selection,
			kind: resolvedKind
		)

		kind = resolvedKind
		searchPattern = pattern
		prefix = resolvedPrefix
		isAtStart = atStart
		searchRange = range
		suffixRange = completionSuffixRange
		originalSuffix = completionSuffixRange.length == 0 ? "" : text.substring(with: completionSuffixRange)
	}

	private static func completionSuffixRange(
		in text: NSString,
		selection: NSRange,
		kind: CompletionKind
	) -> NSRange {
		guard selection.length == 0 else {
			return selection
		}

		let start = selection.location
		var range = NSRange(location: start, length: 0)

		if kind == .nickname,
		   let preferredSuffix = SettingsKeys.Input.tabCompletionSuffix.storedValue,
		   preferredSuffix.isEmpty == false
		{
			let searchRange = NSRange(location: start, length: text.length - start)
			let suffixRange = text.range(of: preferredSuffix, options: [], range: searchRange)

			/* The suffix has to sit near the caret to belong to the word being
			 completed; the search itself runs to the end of the field. */
			if suffixRange.location != NSNotFound,
			   suffixRange.location - start < maximumSuffixDistance
			{
				let beforeSuffix = NSRange(location: start, length: suffixRange.location - start)
				/* A line break between the caret and the suffix ends the word
				 just as a space does. */
				let whitespace = text.rangeOfCharacter(
					from: .whitespacesAndNewlines,
					options: [],
					range: beforeSuffix
				)

				if whitespace.location == NSNotFound {
					range.length = NSMaxRange(suffixRange) - start
				}
			}
		}

		if range.length == 0,
		   SettingsKeys.Input.tabCompletionCutForward.value,
		   start < text.length
		{
			for index in start ..< text.length where isSuffixDelimiter(text.character(at: index)) {
				range.length = index - start
				return range
			}

			range.length = text.length - start
		}

		return range
	}

	/// How far past the caret the preferred suffix may be found and still be
	/// treated as the suffix of the word being completed.
	private static let maximumSuffixDistance = 30

	private static func isWordDelimiter(_ character: UniChar) -> Bool {
		NicknameCompletionDelimiters.isWordDelimiter(character)
	}

	private static func isSuffixDelimiter(_ character: UniChar) -> Bool {
		NicknameCompletionDelimiters.isSuffixDelimiter(character)
	}
}
