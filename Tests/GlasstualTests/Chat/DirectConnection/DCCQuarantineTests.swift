// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreServices
import Foundation
@testable import Glasstual
import Testing

@Suite("DCC quarantine")
struct DCCQuarantineTests {
	@Test("The mark names the app as agent and an other-download type")
	func agentAndType() {
		let properties = DCCQuarantine.properties(for: .init(peerNickname: "nick", hostAddress: "203.0.113.5"))
		#expect(properties[kLSQuarantineAgentNameKey as String] as? String == "Glasstual")
		#expect(properties[kLSQuarantineTypeKey as String] as? String == kLSQuarantineTypeOtherDownload as String)
	}

	@Test("The origin is an irc URL for an address and is omitted for anything else", arguments: [
		("203.0.113.5", "irc://203.0.113.5/"),
		("2001:db8::1", "irc://[2001:db8::1]/"),
		("evil.example/../x", nil),
		("", nil),
	] as [(String, String?)])
	func origin(host: String, expected: String?) {
		#expect(DCCQuarantine.originURL(for: host)?.absoluteString == expected)
	}

	@Test("A received file gets the quarantine attribute")
	func appliesToFile() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try Data("x".utf8).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }

		#expect(DCCQuarantine.apply(to: url, origin: .init(peerNickname: "n", hostAddress: "203.0.113.5")))
		let stored = try url.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
		#expect(stored?[kLSQuarantineAgentNameKey as String] as? String == "Glasstual")
	}

	@Test("A missing file reports failure instead of throwing")
	func missingFile() {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		#expect(DCCQuarantine.apply(to: url, origin: .init(peerNickname: "n", hostAddress: "")) == false)
	}
}
