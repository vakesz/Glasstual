// The MIT License
//
// Copyright (c) 2015 Gwendal Roué
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

protocol TemplateTokenConsumer {
	func parser(_ parser: TemplateParser, shouldContinueAfterParsingToken token: TemplateToken) -> Bool
	func parser(_ parser: TemplateParser, didFailWithError error: Error)
}

final class TemplateParser {
	private enum State {
		case start
		case text(start: String.Index, line: Int)
		case tag(start: String.Index, line: Int)
		case unescapedTag(start: String.Index, line: Int)
		case setDelimitersTag(start: String.Index, line: Int)
	}

	private struct Cursor {
		var delimiters: ParserTagDelimiters
		var state = State.start
		var lineNumber = 1
		var index: String.Index
	}

	private struct ParserTagDelimiters {
		let tagDelimiterPair: TagDelimiterPair
		let tagStartLength: Int
		let tagEndLength: Int
		let unescapedTagStart: String?
		let unescapedTagStartLength: Int
		let unescapedTagEnd: String?
		let unescapedTagEndLength: Int
		let setDelimitersStart: String
		let setDelimitersStartLength: Int
		let setDelimitersEnd: String
		let setDelimitersEndLength: Int

		init(tagDelimiterPair: TagDelimiterPair) {
			self.tagDelimiterPair = tagDelimiterPair
			tagStartLength = tagDelimiterPair.0.count
			tagEndLength = tagDelimiterPair.1.count

			let usesStandardDelimiters = tagDelimiterPair == ("{{", "}}")
			unescapedTagStart = usesStandardDelimiters ? "{{{" : nil
			unescapedTagStartLength = unescapedTagStart?.count ?? 0
			unescapedTagEnd = usesStandardDelimiters ? "}}}" : nil
			unescapedTagEndLength = unescapedTagEnd?.count ?? 0

			setDelimitersStart = "\(tagDelimiterPair.0)="
			setDelimitersStartLength = setDelimitersStart.count
			setDelimitersEnd = "=\(tagDelimiterPair.1)"
			setDelimitersEndLength = setDelimitersEnd.count
		}
	}

	let tokenConsumer: TemplateTokenConsumer
	private let tagDelimiterPair: TagDelimiterPair

	init(tokenConsumer: TemplateTokenConsumer, tagDelimiterPair: TagDelimiterPair) {
		self.tokenConsumer = tokenConsumer
		self.tagDelimiterPair = tagDelimiterPair
	}

	func parse(_ templateString: String, templateID: TemplateID?) {
		var cursor = Cursor(
			delimiters: ParserTagDelimiters(tagDelimiterPair: tagDelimiterPair),
			index: templateString.startIndex
		)

		while cursor.index < templateString.endIndex {
			guard advance(&cursor, in: templateString, templateID: templateID) else { return }
			cursor.index = templateString.index(after: cursor.index)
		}

		finish(cursor, in: templateString, templateID: templateID)
	}

	private func advance(
		_ cursor: inout Cursor,
		in template: String,
		templateID: TemplateID?
	) -> Bool {
		switch cursor.state {
		case .start:
			advanceFromStart(&cursor, in: template)
			return true
		case let .text(start, line):
			return advanceFromText(&cursor, start: start, line: line, in: template, templateID: templateID)
		case let .tag(start, line):
			return advanceFromTag(&cursor, start: start, line: line, in: template, templateID: templateID)
		case let .unescapedTag(start, line):
			return advanceFromUnescapedTag(
				&cursor,
				start: start,
				line: line,
				in: template,
				templateID: templateID
			)
		case let .setDelimitersTag(start, line):
			return advanceFromSetDelimiters(
				&cursor,
				start: start,
				line: line,
				in: template,
				templateID: templateID
			)
		}
	}

	private func advanceFromStart(_ cursor: inout Cursor, in template: String) {
		let index = cursor.index
		if template[index] == "\n" {
			cursor.state = .text(start: index, line: cursor.lineNumber)
			cursor.lineNumber += 1
		} else if isAt(index, cursor.delimiters.unescapedTagStart, in: template) {
			open(
				.unescapedTag(start: index, line: cursor.lineNumber),
				length: cursor.delimiters.unescapedTagStartLength,
				cursor: &cursor,
				in: template
			)
		} else if isAt(index, cursor.delimiters.setDelimitersStart, in: template) {
			open(
				.setDelimitersTag(start: index, line: cursor.lineNumber),
				length: cursor.delimiters.setDelimitersStartLength,
				cursor: &cursor,
				in: template
			)
		} else if isAt(index, cursor.delimiters.tagDelimiterPair.0, in: template) {
			open(
				.tag(start: index, line: cursor.lineNumber),
				length: cursor.delimiters.tagStartLength,
				cursor: &cursor,
				in: template
			)
		} else {
			cursor.state = .text(start: index, line: cursor.lineNumber)
		}
	}

	private func advanceFromText(
		_ cursor: inout Cursor,
		start: String.Index,
		line: Int,
		in template: String,
		templateID: TemplateID?
	) -> Bool {
		let index = cursor.index
		if template[index] == "\n" {
			cursor.lineNumber += 1
			return true
		}

		let nextState: State
		let delimiterLength: Int
		if isAt(index, cursor.delimiters.unescapedTagStart, in: template) {
			nextState = .unescapedTag(start: index, line: cursor.lineNumber)
			delimiterLength = cursor.delimiters.unescapedTagStartLength
		} else if isAt(index, cursor.delimiters.setDelimitersStart, in: template) {
			nextState = .setDelimitersTag(start: index, line: cursor.lineNumber)
			delimiterLength = cursor.delimiters.setDelimitersStartLength
		} else if isAt(index, cursor.delimiters.tagDelimiterPair.0, in: template) {
			nextState = .tag(start: index, line: cursor.lineNumber)
			delimiterLength = cursor.delimiters.tagStartLength
		} else {
			return true
		}

		guard emitText(from: start, to: index, line: line, in: template, templateID: templateID) else { return false }
		open(nextState, length: delimiterLength, cursor: &cursor, in: template)
		return true
	}

	private func advanceFromTag(
		_ cursor: inout Cursor,
		start: String.Index,
		line: Int,
		in template: String,
		templateID: TemplateID?
	) -> Bool {
		if template[cursor.index] == "\n" {
			cursor.lineNumber += 1
			return true
		}
		guard isAt(cursor.index, cursor.delimiters.tagDelimiterPair.1, in: template) else { return true }

		let initialIndex = template.index(start, offsetBy: cursor.delimiters.tagStartLength)
		let initial = template[initialIndex]
		let contentStart = initial == "!" ? initialIndex : template.index(after: initialIndex)
		let content = String(template[(isTagMarker(initial) ? contentStart : initialIndex) ..< cursor.index])
		let type = tokenType(for: initial, content: content, delimiters: cursor.delimiters.tagDelimiterPair)
		let range = start ..< template.index(cursor.index, offsetBy: cursor.delimiters.tagEndLength)
		guard emit(type, line: line, templateID: templateID, template: template, range: range) else { return false }

		close(length: cursor.delimiters.tagEndLength, cursor: &cursor, in: template)
		return true
	}

	private func advanceFromUnescapedTag(
		_ cursor: inout Cursor,
		start: String.Index,
		line: Int,
		in template: String,
		templateID: TemplateID?
	) -> Bool {
		if template[cursor.index] == "\n" {
			cursor.lineNumber += 1
			return true
		}
		guard isAt(cursor.index, cursor.delimiters.unescapedTagEnd, in: template) else { return true }

		let contentStart = template.index(start, offsetBy: cursor.delimiters.unescapedTagStartLength)
		let content = String(template[contentStart ..< cursor.index])
		let range = start ..< template.index(cursor.index, offsetBy: cursor.delimiters.unescapedTagEndLength)
		let type: TemplateToken.`Type` = .unescapedVariable(
			content: content,
			tagDelimiterPair: cursor.delimiters.tagDelimiterPair
		)
		guard emit(type, line: line, templateID: templateID, template: template, range: range) else { return false }

		close(length: cursor.delimiters.unescapedTagEndLength, cursor: &cursor, in: template)
		return true
	}

	private func advanceFromSetDelimiters(
		_ cursor: inout Cursor,
		start: String.Index,
		line: Int,
		in template: String,
		templateID: TemplateID?
	) -> Bool {
		if template[cursor.index] == "\n" {
			cursor.lineNumber += 1
			return true
		}
		guard isAt(cursor.index, cursor.delimiters.setDelimitersEnd, in: template) else { return true }

		let contentStart = template.index(start, offsetBy: cursor.delimiters.setDelimitersStartLength)
		let content = String(template[contentStart ..< cursor.index])
		let newDelimiters = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
		guard newDelimiters.count == 2 else {
			let error = MustacheError(
				kind: .parseError,
				message: "Invalid set delimiters tag",
				templateID: templateID,
				lineNumber: line
			)
			tokenConsumer.parser(self, didFailWithError: error)
			return false
		}

		let range = start ..< template.index(cursor.index, offsetBy: cursor.delimiters.setDelimitersEndLength)
		guard emit(.setDelimiters, line: line, templateID: templateID, template: template, range: range)
		else { return false }
		close(length: cursor.delimiters.setDelimitersEndLength, cursor: &cursor, in: template)
		cursor.delimiters = ParserTagDelimiters(tagDelimiterPair: (newDelimiters[0], newDelimiters[1]))
		return true
	}

	private func tokenType(
		for initial: Character,
		content: String,
		delimiters: TagDelimiterPair
	) -> TemplateToken.`Type` {
		switch initial {
		case "!": .comment
		case "#": .section(content: content, tagDelimiterPair: delimiters)
		case "^": .invertedSection(content: content, tagDelimiterPair: delimiters)
		case "$": .block(content: content)
		case "/": .close(content: content)
		case ">": .partial(content: content)
		case "<": .partialOverride(content: content)
		case "&": .unescapedVariable(content: content, tagDelimiterPair: delimiters)
		case "%": .pragma(content: content)
		default: .escapedVariable(content: content, tagDelimiterPair: delimiters)
		}
	}

	private func emitText(
		from start: String.Index,
		to end: String.Index,
		line: Int,
		in template: String,
		templateID: TemplateID?
	) -> Bool {
		guard start != end else { return true }
		let range = start ..< end
		return emit(
			.text(text: String(template[range])),
			line: line,
			templateID: templateID,
			template: template,
			range: range
		)
	}

	private func emit(
		_ type: TemplateToken.`Type`,
		line: Int,
		templateID: TemplateID?,
		template: String,
		range: Range<String.Index>
	) -> Bool {
		let token = TemplateToken(
			type: type,
			lineNumber: line,
			templateID: templateID,
			templateString: template,
			range: range
		)
		return tokenConsumer.parser(self, shouldContinueAfterParsingToken: token)
	}

	private func finish(_ cursor: Cursor, in template: String, templateID: TemplateID?) {
		switch cursor.state {
		case .start:
			break
		case let .text(start, line):
			_ = emitText(from: start, to: template.endIndex, line: line, in: template, templateID: templateID)
		case let .tag(_, line), let .unescapedTag(_, line), let .setDelimitersTag(_, line):
			let error = MustacheError(
				kind: .parseError,
				message: "Unclosed Mustache tag",
				templateID: templateID,
				lineNumber: line
			)
			tokenConsumer.parser(self, didFailWithError: error)
		}
	}

	private func open(
		_ state: State,
		length: Int,
		cursor: inout Cursor,
		in template: String
	) {
		cursor.state = state
		cursor.index = template.index(cursor.index, offsetBy: length - 1)
	}

	private func close(length: Int, cursor: inout Cursor, in template: String) {
		cursor.state = .start
		cursor.index = template.index(cursor.index, offsetBy: length - 1)
	}

	private func isAt(_ index: String.Index, _ delimiter: String?, in template: String) -> Bool {
		guard let delimiter else { return false }
		return template[index...].hasPrefix(delimiter)
	}

	private func isTagMarker(_ character: Character) -> Bool {
		["!", "#", "^", "$", "/", ">", "<", "&", "%"].contains(character)
	}
}
