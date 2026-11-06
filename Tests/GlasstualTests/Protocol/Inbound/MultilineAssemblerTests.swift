// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("draft/multiline assembly")
struct MultilineAssemblerTests {
	private func batch(opening: String? = nil, type: String = "draft/multiline") -> MessageBatch {
		let batch = MessageBatch()
		batch.batchToken = "m"
		batch.batchType = type
		batch.openingMessage = opening.flatMap { Message(line: $0) }
		return batch
	}

	private func message(_ line: String, in batch: MessageBatch?) throws -> Message {
		var message = try #require(Message(line: line))
		message.parentBatchMessage = batch
		return message
	}

	@Test("Lines become one message joined by line breaks")
	func joinsLines() throws {
		let batch = batch()
		let lines = try [
			message(":alice!u@h PRIVMSG #chan :one", in: batch),
			message(":alice!u@h PRIVMSG #chan :two", in: batch),
			message(":alice!u@h PRIVMSG #chan :three", in: batch),
		]

		let assembled = MultilineAssembler.assemble(lines)

		#expect(assembled.count == 1)
		#expect(assembled.first?.params == ["#chan", "one\ntwo\nthree"])
		#expect(assembled.first?.senderNickname == "alice")
	}

	@Test("A concat line continues the one before it with nothing between")
	func concatenatesLines() throws {
		let batch = batch()
		let lines = try [
			message(":alice!u@h PRIVMSG #chan :long ", in: batch),
			message("@draft/multiline-concat :alice!u@h PRIVMSG #chan :line", in: batch),
			message(":alice!u@h PRIVMSG #chan :next", in: batch),
		]

		let assembled = MultilineAssembler.assemble(lines)

		#expect(assembled.first?.params[1] == "long line\nnext")
		#expect(assembled.first?.messageTags?[MultilineLimits.concatTag] == nil)
	}

	@Test("The message takes its identifier, time and account from the opening line")
	func takesTagsFromTheOpeningLine() throws {
		let batch =
			batch(opening: "@msgid=abc;account=alice;label=g1;time=2026-01-02T03:04:05.000Z :alice!u@h BATCH +m draft/multiline #chan")
		let lines = try [
			message("@msgid=ignored :alice!u@h PRIVMSG #chan :one", in: batch),
			message(":alice!u@h PRIVMSG #chan :two", in: batch),
		]

		let assembled = try #require(MultilineAssembler.assemble(lines).first)

		#expect(assembled.messageIdentifier == "abc")
		#expect(assembled.messageTags?["msgid"] == "abc")
		#expect(assembled.messageTags?["label"] == nil)
		#expect(assembled.parentBatchMessage === batch)
	}

	@Test("A single line is left as it was")
	func singleLineIsUntouched() throws {
		let batch = batch()
		let line = try message(":alice!u@h PRIVMSG #chan :only", in: batch)

		let assembled = MultilineAssembler.assemble([line])

		#expect(assembled.count == 1)
		#expect(assembled.first?.params == ["#chan", "only"])
	}

	@Test("Messages outside a multi-line batch keep their place and order")
	func otherMessagesKeepTheirPlace() throws {
		let batch = batch()
		let lines = try [
			message(":bob!u@h PRIVMSG #chan :before", in: nil),
			message(":alice!u@h PRIVMSG #chan :one", in: batch),
			message(":carol!u@h PRIVMSG #chan :between", in: nil),
			message(":alice!u@h PRIVMSG #chan :two", in: batch),
		]

		let assembled = MultilineAssembler.assemble(lines)

		#expect(assembled.map { $0.params[1] } == ["before", "one\ntwo", "between"])
	}

	@Test("A line for another target or from another sender ends the message")
	func mismatchedLineEndsTheMessage() throws {
		let batch = batch()
		let lines = try [
			message(":alice!u@h PRIVMSG #chan :one", in: batch),
			message(":alice!u@h PRIVMSG #chan :two", in: batch),
			message(":alice!u@h PRIVMSG #other :three", in: batch),
			message(":alice!u@h PRIVMSG #chan :four", in: batch),
		]

		let assembled = MultilineAssembler.assemble(lines)

		#expect(assembled.map { $0.params[1] } == ["one\ntwo", "three", "four"])
	}

	@Test("A line from another sender or of another command ends the message", arguments: [
		":mallory!u@h PRIVMSG #chan :odd",
		":alice!u@h NOTICE #chan :odd",
	])
	func foreignLineEndsTheMessage(_ foreign: String) throws {
		let batch = batch()
		let lines = try [
			message(":alice!u@h PRIVMSG #chan :one", in: batch),
			message(foreign, in: batch),
			message(":alice!u@h PRIVMSG #chan :two", in: batch),
		]

		let assembled = MultilineAssembler.assemble(lines)

		#expect(assembled.map { $0.params[1] } == ["one", "odd", "two"])
	}

	@Test("Two batches are two messages")
	func separateBatchesStaySeparate() throws {
		let first = batch()
		let second = batch()
		let lines = try [
			message(":alice!u@h PRIVMSG #chan :a1", in: first),
			message(":bob!u@h PRIVMSG #chan :b1", in: second),
			message(":alice!u@h PRIVMSG #chan :a2", in: first),
			message(":bob!u@h PRIVMSG #chan :b2", in: second),
		]

		let assembled = MultilineAssembler.assemble(lines)

		#expect(assembled.map { $0.params[1] } == ["a1\na2", "b1\nb2"])
	}

	@Test("Text past the size ceiling is replayed as the lines it is")
	func oversizeTextOverflowsIntoLines() throws {
		let batch = batch()
		let chunk = String(repeating: "x", count: MultilineAssembler.maximumPayloadBytes / 2)
		let lines = try [
			message(":alice!u@h PRIVMSG #chan :\(chunk)", in: batch),
			message(":alice!u@h PRIVMSG #chan :\(chunk)", in: batch),
			message(":alice!u@h PRIVMSG #chan :tail", in: batch),
		]

		let assembled = MultilineAssembler.assemble(lines)

		#expect(assembled.map { $0.params[1] } == [chunk, chunk, "tail"])
	}

	@Test("A batch of another type is not touched")
	func otherBatchTypesAreUntouched() throws {
		let batch = batch(type: "labeled-response")
		let lines = try [
			message(":alice!u@h PRIVMSG #chan :one", in: batch),
			message(":alice!u@h PRIVMSG #chan :two", in: batch),
		]

		#expect(MultilineAssembler.assemble(lines).count == 2)
	}
}
