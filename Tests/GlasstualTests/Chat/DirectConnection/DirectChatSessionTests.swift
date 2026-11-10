// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Network
import Testing

/// A dialling `DirectChatSession` against a loopback listener standing in for
/// the peer. The peer's lines go in over a real socket; what the session made
/// of them is read back from what the session printed.
@MainActor
@Suite("Direct chat session", .timeLimit(.minutes(1)))
struct DirectChatSessionTests {
	private static let messageKinds: Set<UInt> = [
		ChatLineKind.privateMessage.rawValue,
		ChatLineKind.action.rawValue,
	]

	/// The `(kind, body)` pairs of the chat lines the peer's text produced,
	/// leaving out the session's own status lines.
	private func chatLines(on session: TestServerSession) -> [(kind: UInt, body: String)] {
		session.printedLines.compactMap { entry in
			guard let line = entry as? [String: Any],
			      let kind = (line["lineType"] as? NSNumber)?.uintValue,
			      Self.messageKinds.contains(kind),
			      let body = line["messageBody"] as? String
			else { return nil }
			return (kind, body)
		}
	}

	private func dial(
		session: TestServerSession,
		port: UInt16
	) throws -> (session: DirectChatSession, conversation: Conversation) {
		session.openDirectChat(withNickname: "alice", address: TransferFixture.loopbackHost, port: port)
		let conversation = try #require(session.directChatConversation(forNickname: "alice"))
		let connection = try #require(conversation.directChatConnection)

		return (connection, conversation)
	}

	/// Runs `body` against the connection the session's dial produced. The
	/// listener is shut down if no dial ever arrives, so a miss fails the test.
	private func withPeer(
		_ body: (_ peer: NetworkConnection<TCP>, _ session: TestServerSession) async throws -> Void
	) async throws {
		let listening = try await DCCTransport.startListener(portRange: TransferFixture.portRange)
		let session = TestServerSession()
		session.markAsLoggedIn()
		let dialled = try dial(session: session, port: listening.port)
		defer {
			dialled.conversation.closeDirectChatConnection()
			listening.task.cancel()
		}

		try await Eventually.withDeadline(.seconds(20), onExpiry: { listening.task.cancel() }, perform: {
			var accepted: NetworkConnection<TCP>?
			for await connection in listening.connections {
				accepted = connection
				break
			}
			let peer = try #require(accepted, "the session never dialled the listener")
			try await Eventually.until("the session to report the chat connected") { dialled.session.isConnected }
			try await body(peer, session)
		})
	}

	@Test("A CTCP ACTION line is delivered as an action with the frame removed")
	func actionIsUnwrapped() async throws {
		try await withPeer { peer, session in
			try await peer.send(Data("\u{01}ACTION waves\u{01}\n".utf8))

			try await Eventually.until("the action to be printed") { chatLines(on: session).count == 1 }
			let line = try #require(chatLines(on: session).first)
			#expect(line.kind == ChatLineKind.action.rawValue)
			#expect(line.body == "waves")
		}
	}

	/// The sentinel is the last line sent, so once it has been printed every
	/// line before it has been handled, and the list is final.
	@Test("A line of only CR and LF is dropped, and an ordinary line is delivered as a message")
	func emptyLinesAreDropped() async throws {
		try await withPeer { peer, session in
			try await peer.send(Data("\r\n\n\r\nhello\n".utf8))

			try await Eventually.until("the sentinel line to be printed") { !chatLines(on: session).isEmpty }
			let lines = chatLines(on: session)
			#expect(lines.map(\.body) == ["hello"])
			#expect(lines.map(\.kind) == [ChatLineKind.privateMessage.rawValue])
		}
	}

	/// A second `open()` while the first is under way must not dial again. The
	/// listener hands over connections in arrival order, so a barrier dial from
	/// the test, made after the session's own, shows whether anything came
	/// between the two.
	@Test("open() twice starts one connection")
	func openingTwiceDialsOnce() async throws {
		let listening = try await DCCTransport.startListener(portRange: TransferFixture.portRange)
		let session = TestServerSession()
		session.markAsLoggedIn()
		let dialled = try dial(session: session, port: listening.port)
		let barrier = try NWConnection(
			host: NWEndpoint.Host(TransferFixture.loopbackHost),
			port: #require(NWEndpoint.Port(rawValue: listening.port)),
			using: .tcp
		)
		defer {
			barrier.cancel()
			dialled.conversation.closeDirectChatConnection()
			listening.task.cancel()
		}

		dialled.session.open()
		dialled.session.open()
		#expect(dialled.session.state == .connecting)

		try await Eventually.withDeadline(.seconds(20), onExpiry: { listening.task.cancel() }, perform: {
			var arrivals: [UInt16] = []
			var first: NetworkConnection<TCP>?
			for await connection in listening.connections {
				first = connection
				if case let .hostPort(_, port)? = connection.remoteEndpoint {
					arrivals.append(port.rawValue)
				}
				break
			}
			_ = try #require(first, "the session never dialled the listener")

			let (ready, readiness) = AsyncStream<UInt16>.makeStream()
			barrier.stateUpdateHandler = { state in
				if case .ready = state,
				   case let .hostPort(_, port)? = barrier.currentPath?.localEndpoint
				{
					readiness.yield(port.rawValue)
				}
			}
			barrier.start(queue: .global())
			var readyPorts = ready.makeAsyncIterator()
			let barrierPort = try #require(await readyPorts.next(), "the barrier dial never connected")

			for await connection in listening.connections {
				guard case let .hostPort(_, port)? = connection.remoteEndpoint else { continue }
				arrivals.append(port.rawValue)
				if port.rawValue == barrierPort {
					break
				}
			}

			#expect(arrivals.count == 2, "the session dialled \(arrivals.count - 1) times before the barrier")
			#expect(arrivals.last == barrierPort)
		})
	}
}
