// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// What a DCC file offer may carry on the wire, and what is refused.
struct DCCFileTransferRequestParserTests {
	private static let address = "3232235777"

	private func send(_ size: String = "42", port: String = "5000", token: String? = nil) -> DCCFileTransferRequest? {
		DCCFileTransferRequestParser.parse("SEND file \(Self.address) \(port) \(size)" + (token.map { " \($0)" } ?? ""))
	}

	@Test("A size from empty to the maximum is accepted")
	func sizeBounds() {
		let maximum = DCCFileTransferRequestParser.maximumFilesize

		#expect(send("0") != nil)
		#expect(send(String(maximum)) != nil)
		#expect(send(String(maximum + 1)) == nil)
	}

	@Test("A size that is not plain ASCII digits is refused", arguments: [
		"-1", "+5", "1.5", "1e3", "0x10", "", "\u{0663}", "\u{00B2}", "\u{00BD}", "99999999999999999999999",
	])
	func malformedSize(_ size: String) {
		#expect(send(size) == nil)
	}

	@Test("A port outside 1 to 65535 is refused, and zero needs a token", arguments: [
		(("1", nil), true), (("65535", nil), true), (("65536", nil), false), (("0", nil), false),
		(("0", "T9"), true), (("-1", nil), false), (("\u{0663}", nil), false), (("80a", nil), false),
	] as [((port: String, token: String?), Bool)])
	func portBounds(_ offer: (port: String, token: String?), _ accepted: Bool) {
		#expect((send(port: offer.port, token: offer.token) != nil) == accepted)
	}

	@Test("A token loses its T prefix", arguments: [("T123", "123"), ("123", "123")])
	func tokenPrefix(_ token: String, _ expected: String) {
		#expect(send(token: token) == .send(filename: "file", address: "192.168.1.1", port: 5000, filesize: 42, token: expected))
	}

	@Test("A bare T is no token at all")
	func bareT() {
		#expect(send(token: "T") == .send(filename: "file", address: "192.168.1.1", port: 5000, filesize: 42, token: nil))
	}

	@Test("A token that is not plain ASCII digits is refused", arguments: ["Tabc", "\u{00B2}", "T\u{0663}", "12x"])
	func malformedToken(_ token: String) {
		#expect(send(token: token) == nil)
	}

	@Test("Resume and accept carry a port, a position and an optional token")
	func resumeAndAccept() {
		#expect(
			DCCFileTransferRequestParser.parse("RESUME file 5000 12")
				== .resume(filename: "file", port: 5000, position: 12, token: nil)
		)
		#expect(
			DCCFileTransferRequestParser.parse("accept file 0 12 T7")
				== .accept(filename: "file", port: 0, position: 12, token: "7")
		)
		#expect(DCCFileTransferRequestParser.parse("ACCEPT file 0 12") == nil)
		#expect(DCCFileTransferRequestParser.parse("RESUME file 5000 \u{0663}") == nil)
		#expect(DCCFileTransferRequestParser.parse("RESUME file 5000 12 T\u{00B2}") == nil)
	}

	@Test("A chat offer, an unknown verb and an empty line are not file transfers", arguments: [
		"CHAT chat 3232235777 5000", "GET file 1 2 3", "", "SEND",
	])
	func notAFileTransfer(_ source: String) {
		#expect(DCCFileTransferRequestParser.parse(source) == nil)
	}

	@Test("The CTCP spelling of each command")
	func ctcpSpelling() {
		#expect(DCCCommand.send.ctcpCommand == "DCC SEND")
		#expect(DCCCommand.resume.ctcpCommand == "DCC RESUME")
		#expect(DCCCommand.accept.ctcpCommand == "DCC ACCEPT")
		#expect(DCCCommand.chat.ctcpCommand == "DCC CHAT")
		#expect(DCCCommand.secureSend.ctcpCommand == "DCC SSEND")
		#expect(DCCCommand.secureChat.ctcpCommand == "DCC SCHAT")
	}

	@Test("A plain offer is SEND and a secure one SSEND")
	func offerVerb() {
		#expect(DCCCommand.offer(for: .plain) == .send)
		#expect(DCCCommand.offer(for: .secure) == .secureSend)
	}

	@Test("SSEND is understood in its active, passive and passive-reply forms, in any case", arguments: [
		("SSEND file 3232235777 5000 42", (5000, nil)),
		("ssend file 3232235777 0 42 T77", (0, "77")),
		("SsEnD file 3232235777 5000 42 77", (5000, "77")),
	] as [(String, (port: UInt16, token: String?))])
	func secureSend(source: String, expected: (port: UInt16, token: String?)) {
		#expect(DCCFileTransferRequestParser.parse(source) == .send(
			filename: "file", address: "192.168.1.1", port: expected.port, filesize: 42, token: expected.token,
			security: .secure
		))
	}

	@Test("A secure offer keeps a quoted filename and the plain safety rules", arguments: [
		("SSEND \"my file.txt\" 3232235777 5000 42", true),
		("SSEND file 3232235777 0 42", false),
		("SSEND file 3232235777 5000 \u{0663}", false),
		("SSEND file 3232235777 5000 42 T\u{00B2}", false),
		("SSEND file 3232235777 5000 1000000000001", false),
	])
	func secureSendRules(source: String, accepted: Bool) {
		#expect((DCCFileTransferRequestParser.parse(source) != nil) == accepted)
	}

	@Test("A secure offer's filename is sanitized like a plain one's")
	func secureFilename() {
		let plain = DCCFileTransferRequestParser.parse("SEND ../../etc/passwd 3232235777 5000 42")
		let secure = DCCFileTransferRequestParser.parse("SSEND ../../etc/passwd 3232235777 5000 42")
		guard case let .send(plainName, _, _, _, _, _) = plain, case let .send(secureName, _, _, _, _, .secure) = secure else {
			Issue.record("both offers should parse")
			return
		}
		#expect(secureName == plainName)
		#expect(secureName.contains("/") == false)
	}

	@Test("Turbo and reversed forms are recognised so they can be declined", arguments: [
		"TSEND", "TSSEND", "STSEND", "SRECV", "SGET", "SRSEND",
	])
	func unsupportedForms(verb: String) {
		#expect(DCCFileTransferRequestParser.parse("\(verb) file 3232235777 5000 42") == .unsupported(verb: verb))
		#expect(DCCFileTransferRequestParser.parse("\(verb.lowercased()) whatever") == .unsupported(verb: verb))
	}

	@Test("A secure chat offer is not a file transfer")
	func secureChatIsNotAFileTransfer() {
		#expect(DCCFileTransferRequestParser.parse("SCHAT chat 3232235777 5000") == nil)
	}
}
