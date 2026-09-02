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
	@Test("A listener skips ports that are already in use", .timeLimit(.minutes(1)))
	func listenerSkipsPortsThatAreAlreadyInUse() async throws {
		let first = ChatFixture.listeningConnection()
		let second = ChatFixture.listeningConnection()

		await first.start()
		let firstPort = try #require(await ChatFixture.listeningPort(of: first))

		await second.start()
		let secondPort = try #require(await ChatFixture.listeningPort(of: second))

		#expect(secondPort != firstPort)

		await first.close()
		await second.close()
	}

	@Test("Lines cross in both directions, in order", .timeLimit(.minutes(1)))
	func linesCrossInBothDirections() async throws {
		let listening = ChatFixture.listeningConnection()
		var dialled: DCCChatConnection?
		var peer: Task<[String], Never>?
		var replies: [String] = []

		await listening.start()

		events: for await event in listening.events {
			switch event {
			case let .listening(port):
				let connection = ChatFixture.diallingConnection(port: port)
				dialled = connection
				peer = ChatFixture.drive(connection, replying: ["reply one", "reply two"], afterLines: 3)

				await connection.start()
			case .connected:
				try await listening.send(Data("first".utf8))
				try await listening.send(Data("second".utf8))
				try await listening.send(Data("third".utf8))
			case let .line(data):
				replies.append(ChatFixture.decode(data))

				if replies.count == 2 {
					break events
				}
			case .closed:
				break events
			}
		}

		#expect(replies == ["reply one", "reply two"])
		#expect(await peer?.value == ["first", "second", "third"])

		await listening.close()
		await dialled?.close()
	}

	/// The framing is what a chat depends on: a peer that writes a line in
	/// pieces, or several lines in one write, still has to come out as lines.
	@Test("Fragmented and coalesced writes still arrive as lines", .timeLimit(.minutes(1)))
	func fragmentedAndCoalescedWritesArriveAsLines() async throws {
		let listening = ChatFixture.listeningConnection()
		var dialled: DCCChatConnection?
		var peer: Task<[String], Never>?

		await listening.start()

		try await ChatFixture.connect(listening) { connection in
			dialled = connection
			peer = ChatFixture.drive(connection, replying: [], afterLines: 3)
		}

		/* Written unframed, so the fragments arrive as the peer sent them: one
		 line in three writes, then two lines in one. */
		try await listening.write(Data("frag".utf8))
		try await listening.write(Data("mented".utf8))
		try await listening.write(Data(" line\n".utf8))
		try await listening.write(Data("two\nthree\n".utf8))

		#expect(await peer?.value == ["fragmented line", "two", "three"])

		await listening.close()
		await dialled?.close()
	}

	@Test("A peer that hangs up ends the session without an error", .timeLimit(.minutes(1)))
	func aPeerThatHangsUpEndsTheSessionWithoutAnError() async throws {
		let listening = ChatFixture.listeningConnection()
		var dialled: DCCChatConnection?
		var verdict: Task<DCCTransferError??, Never>?

		await listening.start()

		try await ChatFixture.connect(listening) { connection in
			dialled = connection
			verdict = ChatFixture.verdict(of: connection)
		}

		await listening.close()

		let closed = try #require(await verdict?.value)
		#expect(closed == nil)

		await dialled?.close()
	}

	@Test("Cancelling a session ends its events without a verdict", .timeLimit(.minutes(1)))
	func cancellingASessionEndsItsEventsWithoutAVerdict() async throws {
		let listening = ChatFixture.listeningConnection()
		var dialled: DCCChatConnection?
		var collected: Task<[DCCChatEvent], Never>?

		await listening.start()

		try await ChatFixture.connect(listening) { connection in
			dialled = connection
			collected = ChatFixture.allEvents(of: connection)
		}

		await dialled?.close()

		let events = try #require(await collected?.value)

		/* Requiring the stream to have produced the connection first: an empty
		 array would satisfy the absence assertion below without the session
		 ever having happened. */
		#expect(events.isEmpty == false)
		#expect(events.contains {
			if case .connected = $0 {
				true
			} else {
				false
			}
		})
		#expect(events.contains {
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
		var dialled: DCCChatConnection?
		var verdict: Task<DCCTransferError??, Never>?

		await listening.start()

		try await ChatFixture.connect(listening, maximumLineLength: 4096) { connection in
			dialled = connection
			verdict = ChatFixture.verdict(of: connection)
		}

		try await listening.write(Data(repeating: UInt8(ascii: "a"), count: 8192))

		let closed = try #require(await verdict?.value)
		#expect(closed == .badParameter)

		await listening.close()
		await dialled?.close()
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

	static func listeningPort(of connection: DCCChatConnection) async -> UInt16? {
		for await event in connection.events {
			if case let .listening(port) = event {
				return port
			}
		}

		return nil
	}

	/// Dials `listening` once it reports its port, and returns when the two
	/// ends are connected.
	///
	/// `prepare` runs before the dialling side starts, which is where a test
	/// attaches its consumer: an `AsyncStream` takes one, and what is yielded
	/// before it attaches is buffered rather than dropped.
	static func connect(
		_ listening: DCCChatConnection,
		maximumLineLength: Int = 16 * 1024,
		prepare: (DCCChatConnection) -> Void
	) async throws {
		for await event in listening.events {
			switch event {
			case let .listening(port):
				let connection = diallingConnection(port: port, maximumLineLength: maximumLineLength)
				prepare(connection)

				await connection.start()
			case .connected:
				return
			case .line, .closed:
				/* Returning here would leave `prepare` unrun, and every
				 assertion the caller makes on what it attached vacuously true,
				 so the failure is recorded where it happened. */
				Issue.record("the listening side reported \(event) before it connected")

				return
			}
		}

		Issue.record("the listening side never reported a connection")
	}

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

	/// A line as text. The fixture only ever sends UTF-8, so anything else is
	/// the test's own bug and should read as one.
	nonisolated static func decode(_ data: Data) -> String { // nonisolated: pure
		(String(bytes: data, encoding: .utf8) ?? "<not utf-8>").trimmingCharacters(in: .newlines)
	}
}
