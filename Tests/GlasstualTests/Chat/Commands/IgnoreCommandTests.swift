// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** `/ignore` and `/unignore` by mask, by number and with flags: the address
 book editor's ignore entries, from the message field. */
@MainActor
@Suite("/ignore by mask and flags")
struct IgnoreCommandTests {
	@Test("The direct forms parse; a bare nickname keeps its older meaning", arguments: [
		("ignore list", IgnoreCommandRequest.list),
		("ignore *!*@spam.example", .ignore(mask: "*!*@spam.example", flags: [:])),
		("ignore bob +notices -dcc", .ignore(mask: "bob!*@*", flags: [.notices: true, .dcc: false])),
		("ignore bob +shouting", .unknownFlag("+shouting")),
		("unignore 2", .unignoreNumber(2)),
		("unignore *!*@spam.example", .unignoreMask("*!*@spam.example")),
	])
	func parsing(_ testCase: (line: String, request: IgnoreCommandRequest)) throws {
		let parts = testCase.line.split(separator: " ", maxSplits: 1).map(String.init)
		let command = try #require(LocalCommand(typedName: parts[0]))
		#expect(IgnoreCommandRequest(command: command, arguments: parts[1]) == testCase.request)
	}

	@Test("A bare nickname is left to the member lookup", arguments: ["bob", ""])
	func bareNickname(_ arguments: String) {
		#expect(IgnoreCommandRequest(command: .ignore, arguments: arguments) == nil)
	}

	@Test("Adding, flagging, listing and removing edit the address book")
	func editing() {
		let session = TestServerSession()

		session.performIgnoreCommand(.ignore(mask: "*!*@spam.example", flags: [.notices: false]))
		let entry = session.config.ignoreList.first
		#expect(entry?.hostmask == "*!*@spam.example")
		#expect(entry?.ignoreNoticeMessages == false)
		#expect(entry?.ignorePublicMessages == true)

		session.performIgnoreCommand(.ignore(mask: "*!*@SPAM.example", flags: [.mute: true]))
		#expect(session.config.ignoreList.count == 1)
		#expect(session.config.ignoreList.first?.muteMessages == true)

		session.performIgnoreCommand(.unignoreNumber(1))
		#expect(session.config.ignoreList.isEmpty)
	}
}
