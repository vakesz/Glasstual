import Foundation

struct InteractiveFixture {
	let kind: ScenarioKind
	var stage = 0
	var dccPort: UInt16 = 0
	var usesPassiveDCC = false
	var dccFilename = "e2e-transfer.bin"
	var dccListeningPort: UInt16?
	var finished: Bool {
		switch kind {
		case .burstResponsiveness: stage == 4
		case .dccSuccess, .dccCancel: stage == 2
		default: false
		}
	}

	mutating func receive(_ line: String, joined: Bool) throws -> [String]? {
		guard line.hasPrefix("PRIVMSG fixture :") else { return nil }
		if kind == .burstResponsiveness {
			let expected = stage == 0 ? "E2E_BURST_START" : "E2E_BURST_SWITCH_\(stage)"
			guard joined, stage < 4, line == "PRIVMSG fixture :" + expected else {
				throw HarnessFailure.assertion("Burst switching fixture ordering mismatch")
			}
			stage += 1
			return [":fixture!fixture@localhost PRIVMSG #e2e :\(expected)_ACK"]
		}
		if kind.dcc {
			if stage == 0, line == "PRIVMSG fixture :E2E_DCC_OFFER", usesPassiveDCC || dccPort > 0 {
				stage = 1
				let port = usesPassiveDCC ? 0 : dccPort
				let token = usesPassiveDCC ? " 424242" : ""
				return [
					":fixture!fixture@localhost PRIVMSG e2euser :\u{01}DCC SEND \(dccFilename) 2130706433 \(port) 100003\(token)\u{01}",
				]
			}
			if usesPassiveDCC, stage == 1, line.hasPrefix("PRIVMSG fixture :\u{01}DCC SEND ") {
				let tokens = line.replacingOccurrences(of: "\u{01}", with: "").split(separator: " ")
				guard tokens.count == 9,
				      tokens[2] == ":DCC",
				      tokens[3] == "SEND",
				      tokens[4] == Substring(dccFilename),
				      tokens[5] == "2130706433",
				      let port = UInt16(tokens[6]),
				      port > 0,
				      tokens[7] == "100003",
				      tokens[8] == "424242",
				      dccListeningPort == nil
				else { throw HarnessFailure.assertion("Passive DCC response mismatch") }
				dccListeningPort = port
				return []
			}
			guard stage == 1, line == "PRIVMSG fixture :E2E_DCC_DONE" else {
				throw HarnessFailure.assertion("DCC fixture ordering mismatch")
			}
			stage = 2
			return [":e2e.local NOTICE e2euser :E2E_DCC_FINISHED"]
		}
		throw HarnessFailure.assertion("Unexpected interactive fixture command")
	}

	static func burstBatch(_ index: Int) -> [String] {
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
