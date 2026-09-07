import Foundation

struct InteractiveFixture {
	let kind: ScenarioKind
	var stage = 0
	var dccPort: UInt16 = 0
	var finished: Bool {
		switch kind {
		case .pluginSmiley: stage == 3
		case .burstResponsiveness: stage == 4
		case .dccSuccess, .dccCancel: stage == 2
		default: false
		}
	}

	mutating func receive(_ line: String, joined: Bool) throws -> [String]? {
		guard line.hasPrefix("PRIVMSG fixture :E2E_") else { return nil }
		if kind == .pluginSmiley {
			let tokens = ["E2E_SMILEY_OFF", "E2E_SMILEY_ON", "E2E_SMILEY_OFF_AGAIN"]
			guard joined, stage < tokens.count, line == "PRIVMSG fixture :" + tokens[stage] else {
				throw HarnessFailure.assertion("Smiley fixture ordering mismatch")
			}
			let marker = tokens[stage]
			stage += 1
			return [":fixture!fixture@localhost PRIVMSG #e2e :\(marker) :-)"]
		}
		if kind == .burstResponsiveness {
			let expected = stage == 0 ? "E2E_BURST_START" : "E2E_BURST_SWITCH_\(stage)"
			guard joined, stage < 4, line == "PRIVMSG fixture :" + expected else {
				throw HarnessFailure.assertion("Burst switching fixture ordering mismatch")
			}
			stage += 1
			return [":fixture!fixture@localhost PRIVMSG #e2e :\(expected)_ACK"]
		}
		if kind.dcc {
			if stage == 0, line == "PRIVMSG fixture :E2E_DCC_OFFER", dccPort > 0 {
				stage = 1
				return [
					":fixture!fixture@localhost PRIVMSG e2euser :\u{01}DCC SEND e2e-transfer.bin 2130706433 \(dccPort) 100003\u{01}",
				]
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
