/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** The gate that replaced the semaphore the TLS verify block used to park on.

 The connection completes the handshake now and holds the traffic instead, so
 what matters is that a peer the user rejects never gets a word through, and
 that a peer they accept has everything it said delivered in the order it
 arrived.

 The mutating calls are hoisted out of `#expect`: the macro evaluates its
 expression in a closure, where the gate would be immutable. */
@Suite("Connection trust gate")
nonisolated struct ConnectionTrustGateTests {
	private enum Line: Equatable, Sendable {
		case received(String)
		case closedReadStream
	}

	@Test("Nothing is held until the question is asked")
	func trafficFlowsUntilTheGateCloses() {
		var gate = ConnectionTrustGate<Line>()
		let heldEvent = gate.hold(.received("PING"))
		let heldWrite = gate.holdWrite(Data("PONG\r\n".utf8))

		#expect(gate.isPending == false)
		#expect(heldEvent == false)
		#expect(heldWrite == false)
	}

	@Test("A rejected certificate delivers nothing and closes the connection")
	func rejectionDeliversNothingAndCloses() {
		var gate = ConnectionTrustGate<Line>()
		let began = gate.begin()
		let heldFirst = gate.hold(.received(":server 001 nick :Welcome"))
		let heldSecond = gate.hold(.received(":server NOTICE nick :hello"))
		let heldWrite = gate.holdWrite(Data("NICK nick\r\n".utf8))
		let outcome = gate.resolve(trusted: false)
		let replayed = gate.nextWrite()

		#expect(began)
		#expect(heldFirst)
		#expect(heldSecond)
		#expect(heldWrite)
		#expect(outcome.closes)
		#expect(outcome.deliver.isEmpty)
		#expect(gate.isPending == false)
		// Nothing survives the rejection to be replayed later.
		#expect(replayed == nil)
	}

	@Test("An accepted certificate delivers what arrived, in order")
	func acceptanceDeliversWhatWasHeldInOrder() {
		var gate = ConnectionTrustGate<Line>()
		let began = gate.begin()

		var allHeld = true
		for index in 0 ..< 50 {
			allHeld = gate.hold(.received("line-\(index)")) && allHeld
		}
		allHeld = gate.hold(.closedReadStream) && allHeld

		let outcome = gate.resolve(trusted: true)

		#expect(began)
		#expect(allHeld)
		#expect(outcome.closes == false)
		#expect(outcome.deliver.count == 51)
		#expect(outcome.deliver.last == .closedReadStream)
		#expect(Array(outcome.deliver.dropLast()) == (0 ..< 50).map { Line.received("line-\($0)") })
	}

	@Test("Writes held during the wait are sent afterwards, in order")
	func heldWritesAreSentInOrder() {
		var gate = ConnectionTrustGate<Line>()
		let began = gate.begin()
		let lines = ["CAP LS 302\r\n", "NICK nick\r\n", "USER nick 0 * :nick\r\n"]

		var allHeld = true
		for line in lines {
			allHeld = gate.holdWrite(Data(line.utf8)) && allHeld
		}

		// A closed gate hands nothing back: the peer is not vouched for yet.
		let earlyWrite = gate.nextWrite()
		let outcome = gate.resolve(trusted: true)

		/* Drained one at a time, which is the send discipline the connection
		 already had: one write in flight, the next when the transport reports
		 the previous one sent. */
		var drained: [String?] = []
		while let next = gate.nextWrite() {
			drained.append(String(bytes: next, encoding: .utf8))
		}

		#expect(began)
		#expect(allHeld)
		#expect(earlyWrite == nil)
		#expect(outcome.closes == false)
		#expect(drained == lines)
	}

	@Test("The question is only asked once while it is outstanding")
	func aSecondQuestionIsRefused() {
		var gate = ConnectionTrustGate<Line>()
		let first = gate.begin()
		let second = gate.begin()

		_ = gate.resolve(trusted: true)

		// A new handshake on the same socket may ask again.
		let afterAnswer = gate.begin()

		#expect(first)
		#expect(second == false)
		#expect(afterAnswer)
	}

	@Test("An answer with no question outstanding changes nothing")
	func resolvingWithoutAQuestionIsInert() {
		var gate = ConnectionTrustGate<Line>()
		let outcome = gate.resolve(trusted: false)

		#expect(outcome.closes == false)
		#expect(outcome.deliver.isEmpty)
	}
}
