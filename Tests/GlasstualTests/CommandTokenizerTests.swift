/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Testing

@Suite("Command tokenizer")
struct CommandTokenizerTests {
	@Test("Tokens are consumed left to right across whitespace runs")
	func tokensAreConsumedInOrder() {
		var tokenizer = CommandTokenizer("PRIVMSG   #swift  hello")

		#expect(tokenizer.nextToken() == "PRIVMSG")
		#expect(tokenizer.remainder == "#swift  hello")
		#expect(tokenizer.nextToken() == "#swift")
		#expect(tokenizer.nextToken() == "hello")
		#expect(tokenizer.remainder.isEmpty)
	}

	@Test("An exhausted tokenizer keeps returning the empty string")
	func exhaustionIsNotAnError() {
		var tokenizer = CommandTokenizer("")

		#expect(tokenizer.nextToken() == "")
		#expect(tokenizer.nextToken() == "")
	}

	@Test("Uppercasing is applied to the consumed token")
	func uppercaseTokenIsConsumed() {
		var tokenizer = CommandTokenizer("privmsg #swift")

		#expect(tokenizer.nextUppercaseToken() == "PRIVMSG")
		#expect(tokenizer.remainder == "#swift")
	}

	@Test("A newline is part of a token, not a separator")
	func newlinesAreNotSeparators() {
		var tokenizer = CommandTokenizer("a\nb c")

		#expect(tokenizer.nextToken() == "a\nb")
	}

	@Test("Multi-scalar characters stay whole")
	func graphemeClustersSurvive() {
		var tokenizer = CommandTokenizer("👨‍👩‍👧 tail")

		#expect(tokenizer.nextToken() == "👨‍👩‍👧")
		#expect(tokenizer.nextToken() == "tail")
	}

	@Test("A double-quoted token is unwrapped and the trailing space consumed")
	func doubleQuotedTokenIsUnwrapped() {
		var tokenizer = CommandTokenizer(#""one two"   tail"#)

		#expect(tokenizer.nextQuotedToken() == "one two")
		#expect(tokenizer.remainder == "tail")
	}

	@Test("An escaped quote inside the token loses its backslash")
	func escapedQuoteIsResolved() {
		var tokenizer = CommandTokenizer(#""one\" two"   tail"#)

		#expect(tokenizer.nextQuotedToken() == #"one" two"#)
		#expect(tokenizer.remainder == "tail")
	}

	@Test("A closing quote not followed by whitespace is not a closing quote")
	func unterminatedTokenLeavesTheCursorAlone() {
		var tokenizer = CommandTokenizer(#""value"suffix"#)

		#expect(tokenizer.nextQuotedToken() == "")
		#expect(tokenizer.remainder == #""value"suffix"#)
	}

	@Test("Single quotes only open a token when the option asks for them")
	func singleQuotesAreOptional() {
		var withoutOption = CommandTokenizer("'one two' next")

		#expect(withoutOption.nextQuotedToken() == "")

		var withOption = CommandTokenizer("'one two' next")
		let options: CommandTokenizer.Options = [.singleQuotes, .terminatesWithSpace, .collapseSlashes]

		#expect(withOption.nextQuotedToken(options: options) == "one two")
		#expect(withOption.remainder == "next")
	}

	@Test("Without terminatesWithSpace the first unescaped quote closes the token")
	func terminationOptionIsHonored() {
		var tokenizer = CommandTokenizer(#""value"suffix"#)

		#expect(tokenizer.nextQuotedToken(options: [.doubleQuotes]) == "value")
		#expect(tokenizer.remainder == "suffix")
	}

	@Test("Backslash runs are halved when collapsing is asked for")
	func slashRunsCollapse() {
		var collapsing = CommandTokenizer(#""a\\\\b" tail"#)

		#expect(collapsing.nextQuotedToken() == #"a\\b"#)

		var verbatim = CommandTokenizer(#""a\\\\b" tail"#)
		let options: CommandTokenizer.Options = [.doubleQuotes, .terminatesWithSpace]

		#expect(verbatim.nextQuotedToken(options: options) == #"a\\\\b"#)
	}

	@Test("A token with no closing quote yields nothing")
	func missingClosingQuoteYieldsNothing() {
		var tokenizer = CommandTokenizer(#""unterminated"#)

		#expect(tokenizer.nextQuotedToken() == "")
		#expect(tokenizer.remainder == #""unterminated"#)
	}

	@Test("The first token is read without a cursor")
	func firstTokenIgnoresSurroundingWhitespace() {
		#expect("  JOIN   #swift  ".firstToken == "JOIN")
		#expect("   ".firstToken == "")
		#expect("".firstToken == "")
	}
}

@Suite("Attributed command tokenizer")
struct AttributedCommandTokenizerTests {
	private let marker = NSAttributedString.Key("CommandTokenizerTestsMarker")

	@Test("Consuming a token leaves the rest of the attributed line in place")
	func attributedTokenConsumesSource() {
		let source = NSMutableAttributedString(
			string: "JOIN   #swift",
			attributes: [marker: "preserved"]
		)

		#expect(source.nextTokenAsString() == "JOIN")
		#expect(source.string == "#swift")
		#expect(source.attribute(marker, at: 0, effectiveRange: nil) as? String == "preserved")
	}

	@Test("Consumption is measured in UTF-16 units, not characters")
	func consumptionUsesUTF16Offsets() {
		let source = NSMutableAttributedString(string: "😀😀 tail")

		#expect(source.nextTokenAsString() == "😀😀")
		#expect(source.string == "tail")
	}

	@Test("A quoted token is unwrapped and consumed")
	func attributedQuotedTokenIsUnwrapped() {
		let source = NSMutableAttributedString(string: #""one two"   tail"#)

		#expect(source.nextQuotedTokenAsString() == "one two")
		#expect(source.string == "tail")
	}

	@Test("An unquoted line is left untouched by the quoted read")
	func attributedQuotedTokenLeavesUnquotedInputAlone() {
		let source = NSMutableAttributedString(string: "plain text")

		#expect(source.nextQuotedTokenAsString() == "")
		#expect(source.string == "plain text")
	}

	@Test("An empty line consumes nothing")
	func emptyAttributedLineIsNotMutated() {
		let source = NSMutableAttributedString(string: "")

		#expect(source.nextTokenAsString() == "")
		#expect(source.string == "")
	}
}
