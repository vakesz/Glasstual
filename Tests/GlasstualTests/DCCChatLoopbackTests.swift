/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Drives two `DCCChatConnection` actors against each other over the loopback
/// interface. DCC CHAT has no acknowledgement and no length to count down, so
/// what has to be proven is the framing: whole lines, in order, both ways, and
/// a clean end when a peer hangs up.
///
/// Each event stream has exactly one consumer: the test body iterates the
/// listening side, and a task owns the dialling side.
@Suite("DCC CHAT over loopback")
struct DCCChatLoopbackTests {
	@Test("Lines cross in both directions, in order", .timeLimit(.minutes(1)))
	func linesCrossInBothDirections() async throws {
		let listening = ChatFixture.listeningConnection()
		var events = listening.events.makeAsyncIterator()

		await listening.start()

		let port = try #require(await ChatFixture.boundPort(from: &events))
		let dialled = ChatFixture.diallingConnection(port: port)
		let peer = ChatFixture.drive(dialled, replying: ["reply one", "reply two"], afterLines: 3)

		await dialled.start()

		#expect(await ChatFixture.waitForConnection(from: &events))

		try await listening.send(Data("first".utf8))
		try await listening.send(Data("second".utf8))
		try await listening.send(Data("third".utf8))

		let replies = await ChatFixture.lines(from: &events, count: 2)

		#expect(replies == ["reply one", "reply two"])
		#expect(await peer.value == ["first", "second", "third"])

		await listening.close()
		await dialled.close()
	}

	/// The framing is what a chat depends on: a peer that writes a line in
	/// pieces, or several lines in one write, still has to come out as lines.
	@Test("Fragmented and coalesced writes still arrive as lines", .timeLimit(.minutes(1)))
	func fragmentedAndCoalescedWritesArriveAsLines() async throws {
		let listening = ChatFixture.listeningConnection()
		var events = listening.events.makeAsyncIterator()

		await listening.start()

		let port = try #require(await ChatFixture.boundPort(from: &events))
		let dialled = ChatFixture.diallingConnection(port: port)
		let peer = ChatFixture.drive(dialled, replying: [], afterLines: 3)

		await dialled.start()

		#expect(await ChatFixture.waitForConnection(from: &events))

		/* Written unframed, so the fragments arrive as the peer sent them: one
		 line in three writes, then two lines in one. */
		try await listening.write(Data("frag".utf8))
		try await listening.write(Data("mented".utf8))
		try await listening.write(Data(" line\n".utf8))
		try await listening.write(Data("two\nthree\n".utf8))

		#expect(await peer.value == ["fragmented line", "two", "three"])

		await listening.close()
		await dialled.close()
	}

	@Test("A peer that hangs up ends the session without an error", .timeLimit(.minutes(1)))
	func aPeerThatHangsUpEndsTheSessionWithoutAnError() async throws {
		let listening = ChatFixture.listeningConnection()
		var events = listening.events.makeAsyncIterator()

		await listening.start()

		let port = try #require(await ChatFixture.boundPort(from: &events))
		let dialled = ChatFixture.diallingConnection(port: port)
		let verdict = ChatFixture.verdict(of: dialled)

		await dialled.start()

		#expect(await ChatFixture.waitForConnection(from: &events))

		await listening.close()

		let closed = try #require(await verdict.value)
		#expect(closed == nil)

		await dialled.close()
	}

	@Test("Cancelling a session ends its events without a verdict", .timeLimit(.minutes(1)))
	func cancellingASessionEndsItsEventsWithoutAVerdict() async throws {
		let listening = ChatFixture.listeningConnection()
		var events = listening.events.makeAsyncIterator()

		await listening.start()

		let port = try #require(await ChatFixture.boundPort(from: &events))
		let dialled = ChatFixture.diallingConnection(port: port)
		let collected = ChatFixture.allEvents(of: dialled)

		await dialled.start()

		#expect(await ChatFixture.waitForConnection(from: &events))

		await dialled.close()

		let events2 = await collected.value
		#expect(events2.contains {
			if case .closed = $0 {
				true
			} else {
				false
			}
		} == false)

		await listening.close()
	}

	@Test("A peer that never sends a newline is cut off at the cap", .timeLimit(.minutes(1)))
	func aPeerThatNeverSendsANewlineIsCutOff() async throws {
		let listening = ChatFixture.listeningConnection(maximumLineLength: 4096)
		var events = listening.events.makeAsyncIterator()

		await listening.start()

		let port = try #require(await ChatFixture.boundPort(from: &events))
		let dialled = ChatFixture.diallingConnection(port: port, maximumLineLength: 4096)
		let verdict = ChatFixture.verdict(of: dialled)

		await dialled.start()

		#expect(await ChatFixture.waitForConnection(from: &events))

		try await listening.write(Data(repeating: UInt8(ascii: "a"), count: 8192))

		let closed = try #require(await verdict.value)
		#expect(closed == .badParameter)

		await listening.close()
		await dialled.close()
	}
}

/// Scaffolding for the loopback chats.
enum ChatFixture {
	static let loopbackHost = "127.0.0.1"
	/// A range well clear of anything a developer machine is likely to serve,
	/// and clear of the one the transfer tests use.
	static let portRange: ClosedRange<UInt16> = 49460 ... 49660

	static func listeningConnection(maximumLineLength: Int = 16 * 1024) -> DCCChatConnection {
		DCCChatConnection(configuration: DCCChatConnection.Configuration(
			endpoint: .listen(portRange: portRange),
			maximumLineLength: maximumLineLength,
			sendTimeout: .seconds(20)
		))
	}

	static func diallingConnection(
		port: UInt16,
		maximumLineLength: Int = 16 * 1024
	) -> DCCChatConnection {
		DCCChatConnection(configuration: DCCChatConnection.Configuration(
			endpoint: .connect(host: loopbackHost, port: port, interfaceName: nil, timeout: .seconds(20)),
			maximumLineLength: maximumLineLength,
			sendTimeout: .seconds(20)
		))
	}

	// MARK: - Reading one side from the test body

	static func boundPort(from events: inout AsyncStream<DCCChatEvent>.Iterator) async -> UInt16? {
		while let event = await events.next() {
			if case let .listening(port) = event {
				return port
			}
		}

		return nil
	}

	static func waitForConnection(from events: inout AsyncStream<DCCChatEvent>.Iterator) async -> Bool {
		while let event = await events.next() {
			if case .connected = event {
				return true
			}
		}

		return false
	}

	static func lines(
		from events: inout AsyncStream<DCCChatEvent>.Iterator,
		count: Int
	) async -> [String] {
		var lines: [String] = []

		while lines.count < count, let event = await events.next() {
			guard case let .line(data) = event else {
				continue
			}

			lines.append(decode(data))
		}

		return lines
	}

	// MARK: - Driving the other side from a task

	/// Reads `connection` until it has `expected` lines, sends `replies`, and
	/// returns what it read.
	static func drive(
		_ connection: DCCChatConnection,
		replying replies: [String],
		afterLines expected: Int
	) -> Task<[String], Never> {
		let events = connection.events

		return Task {
			var lines: [String] = []

			for await event in events {
				guard case let .line(data) = event else {
					continue
				}

				lines.append(decode(data))

				guard lines.count == expected else {
					continue
				}

				for reply in replies {
					try? await connection.send(Data(reply.utf8))
				}

				return lines
			}

			return lines
		}
	}

	/// The session's terminal event: the outer optional is `nil` when the
	/// stream ended without one, the inner when it ended cleanly.
	static func verdict(of connection: DCCChatConnection) -> Task<DCCTransferError??, Never> {
		let events = connection.events

		return Task {
			for await event in events {
				if case let .closed(error) = event {
					return error
				}
			}

			return DCCTransferError??.none
		}
	}

	static func allEvents(of connection: DCCChatConnection) -> Task<[DCCChatEvent], Never> {
		let events = connection.events

		return Task {
			var collected: [DCCChatEvent] = []

			for await event in events {
				collected.append(event)
			}

			return collected
		}
	}

	private static func decode(_ data: Data) -> String {
		String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
	}
}
