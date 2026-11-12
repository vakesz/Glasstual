import Foundation

struct InteractiveFixture {
	let mode: FixtureMode
	var stage = 0
	var dccPort: UInt16 = 0
	var usesPassiveDCC = false
	/// One name per file the DCC peer offers, in order.
	var dccFilenames = ["e2e-transfer.bin"]
	/// The ports the application said it listens on, one per passive offer it answered.
	private(set) var dccListeningPorts: [UInt16] = []
	/// Files offered so far.
	private(set) var offers = 0
	/// An offer the fixture has written but not sent: an XDCC bot takes its
	/// time, and the scenario releases it once it has seen the request waiting.
	private(set) var heldOffer: String?
	var finished: Bool {
		switch mode {
		case .burstResponsiveness: stage == 4
		default: mode.dcc && stage == 2
		}
	}

	/// The words that ask the fixture for its next file.
	private var offerRequest: String {
		if mode == .xdccRequest {
			return "XDCC SEND #1"
		}
		return offers == 0 ? "E2E_DCC_OFFER" : "E2E_DCC_OFFER_AGAIN"
	}

	private var dccVerb: String {
		if mode.directChat {
			return "SCHAT"
		}
		return mode.secureDCC ? "SSEND" : "SEND"
	}

	/// What follows the verb in the fixture's offer `number`, from 1: a file
	/// and its size, or the chat protocol. A passive offer names port zero
	/// and a token.
	private func offerArguments(_ number: Int) -> String {
		let port = usesPassiveDCC ? 0 : dccPort
		let token = usesPassiveDCC ? " " + Self.token(number) : ""
		if mode.directChat {
			return "CHAT 2130706433 \(port)\(token)"
		}
		return "\(dccFilenames[number - 1]) 2130706433 \(port) 100003\(token)"
	}

	/// The port the application listens on, from its answer to passive offer
	/// `number`, or `nil` where the answer does not match the offer.
	private func listeningPort(in line: String, answering number: Int) -> UInt16? {
		let tokens = line.replacingOccurrences(of: "\u{01}", with: "").split(separator: " ").map(String.init)
		let leading = [mode.directChat ? "chat" : dccFilenames[number - 1], "2130706433"]
		let trailing = mode.directChat ? [Self.token(number)] : ["100003", Self.token(number)]
		guard tokens.count == 4 + leading.count + 1 + trailing.count, tokens[2] == ":DCC",
		      Array(tokens[4 ..< 6]) == leading, Array(tokens.suffix(trailing.count)) == trailing,
		      let port = UInt16(tokens[6]), port > 0
		else { return nil }
		return port
	}

	/// The token of the passive offer for file `number`, from 1.
	private static func token(_ number: Int) -> String {
		"42424\(number)"
	}

	mutating func receive(_ line: String, joined: Bool) throws -> [String]? {
		guard line.hasPrefix("PRIVMSG fixture :") else { return nil }
		if mode == .burstResponsiveness {
			let expected = stage == 0 ? "E2E_BURST_START" : "E2E_BURST_SWITCH_\(stage)"
			guard joined, stage < 4, line == "PRIVMSG fixture :" + expected else {
				throw HarnessFailure.assertion("Burst switching fixture ordering mismatch")
			}
			stage += 1
			return [":fixture!fixture@localhost PRIVMSG #e2e :\(expected)_ACK"]
		}
		if mode.dcc {
			return try receiveDCC(line)
		}
		throw HarnessFailure.assertion("Unexpected interactive fixture command")
	}

	private mutating func receiveDCC(_ line: String) throws -> [String] {
		// Every offer so far has been answered, or needed no answer.
		let answered = usesPassiveDCC == false || dccListeningPorts.count == offers
		if stage < 2, offers < dccFilenames.count, answered, line == "PRIVMSG fixture :" + offerRequest,
		   usesPassiveDCC || dccPort > 0
		{
			stage = 1
			offers += 1
			let offer = ":fixture!fixture@localhost PRIVMSG e2euser :\u{01}DCC \(dccVerb) \(offerArguments(offers))\u{01}"
			guard mode == .xdccRequest else { return [offer] }
			heldOffer = offer
			return []
		}
		if usesPassiveDCC, stage == 1, line.hasPrefix("PRIVMSG fixture :\u{01}DCC \(dccVerb) ") {
			guard let port = listeningPort(in: line, answering: offers), dccListeningPorts.count == offers - 1
			else { throw HarnessFailure.assertion("Passive DCC response mismatch") }
			dccListeningPorts.append(port)
			return []
		}
		guard stage == 1, offers == dccFilenames.count, answered, line == "PRIVMSG fixture :E2E_DCC_DONE" else {
			throw HarnessFailure.assertion("DCC fixture ordering mismatch")
		}
		stage = 2
		return [":e2e.local NOTICE e2euser :E2E_DCC_FINISHED"]
	}

	nonisolated static func burstBatch(_ index: Int) -> [String] { // nonisolated: pure
		let names = (index * 100 ..< (index + 1) * 100).map { "member\($0)" }
		var lines = stride(from: 0, to: names.count, by: 20).map {
			":e2e.local 353 e2euser = #e2e :" + names[$0 ..< $0 + 20].joined(separator: " ")
		}
		lines += (index * 50 ..< (index + 1) * 50)
			.map { ":fixture!fixture@localhost PRIVMSG #e2e :E2E_BURST_MESSAGE_\($0)" }
		if index == 99 {
			lines += [":e2e.local 353 e2euser = #e2e :e2euser fixture", ":e2e.local 366 e2euser #e2e :End of NAMES",
			          ":fixture!fixture@localhost PRIVMSG #e2e :E2E_BURST_END"]
		}
		return lines
	}
}
