// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Testing

struct LineFramerTests {
	@Test("The line limit applies regardless of read boundaries", arguments: 0 ... 5)
	func rejectsOversizedLine(splitAt offset: Int) throws {
		var framer = LineFramer(maximumLineLength: 4, stripsCarriageReturns: false, dropsEmptyLines: false)
		let payload = Data("abcde\n".utf8)

		do {
			_ = try framer.lines(appending: Data(payload.prefix(offset)))
			_ = try framer.lines(appending: Data(payload.dropFirst(offset)))
			Issue.record("A five-byte line exceeded the four-byte limit")
		} catch {
			#expect(error.completedLines.isEmpty)
		}
	}

	@Test("A line exactly at the limit is accepted across every read boundary", arguments: 0 ... 5)
	func acceptsLimitLengthLine(splitAt offset: Int) throws {
		var framer = LineFramer(maximumLineLength: 4, stripsCarriageReturns: false, dropsEmptyLines: false)
		let payload = Data("abcd\n".utf8)
		var lines = try framer.lines(appending: Data(payload.prefix(offset)))
		lines += try framer.lines(appending: Data(payload.dropFirst(offset)))

		#expect(lines == [Data("abcd".utf8)])
		#expect(framer.hasPartialLine == false)
	}

	@Test("An overrun preserves preceding complete lines and drops subsequent lines")
	func overrunReportsOnlyPrecedingLines() throws {
		var framer = LineFramer(maximumLineLength: 4, stripsCarriageReturns: true, dropsEmptyLines: true)

		do {
			_ = try framer.lines(appending: Data("ok\r\nabcde\nafter\n".utf8))
			Issue.record("The oversized complete line should fail framing")
		} catch {
			#expect(error.completedLines == [Data("ok".utf8)])
		}
	}

	@Test("IRC framing strips repeated CRs and empty lines across reads")
	func ircLineEndings() throws {
		var framer = LineFramer(maximumLineLength: 16, stripsCarriageReturns: true, dropsEmptyLines: true)
		#expect(try framer.lines(appending: Data("hello\r".utf8)).isEmpty)
		#expect(framer.hasPartialLine)
		#expect(try framer.lines(appending: Data("\r\n\r\nworld\n".utf8)) == [Data("hello".utf8), Data("world".utf8)])
		#expect(framer.hasPartialLine == false)
	}

	@Test("DCC framing preserves carriage returns and empty lines")
	func directChatLineEndings() throws {
		var framer = LineFramer(maximumLineLength: 16, stripsCarriageReturns: false, dropsEmptyLines: false)
		#expect(try framer.lines(appending: Data("hello\r\n\n".utf8)) == [Data("hello\r".utf8), Data()])
	}

	@Test("Reset discards an unfinished line")
	func resetDiscardsPartialLine() throws {
		var framer = LineFramer(maximumLineLength: 4, stripsCarriageReturns: false, dropsEmptyLines: false)
		#expect(try framer.lines(appending: Data("old".utf8)).isEmpty)
		framer.reset()
		#expect(framer.hasPartialLine == false)
		#expect(try framer.lines(appending: Data("new\n".utf8)) == [Data("new".utf8)])
	}
}
