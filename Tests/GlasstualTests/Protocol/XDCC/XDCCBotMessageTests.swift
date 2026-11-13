// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("XDCC bot message")
struct XDCCBotMessageTests {
	@Test("Bot notices are read in iroffer's wording", arguments: [
		(
			"** Sending you pack #5 (\"file.mkv\"), which is 700MB. (resume supported)",
			XDCCBotMessage.sending(pack: 5, filename: "file.mkv", sizeText: "700MB")
		),
		(
			"** Sending you pack #12 (\"name with spaces.zip\"), which is 1.2GB.",
			.sending(pack: 12, filename: "name with spaces.zip", sizeText: "1.2GB")
		),
		(
			"** All Slots Full, Added you to the main queue for pack 5 (\"file.mkv\") in position 3. "
				+ "To Remove yourself at a later time type \"/MSG Bot XDCC REMOVE 5\".",
			.queued(pack: 5, filename: "file.mkv", position: 3)
		),
		(
			"** Added you to the idle queue for pack 9.",
			.queued(pack: 9, filename: nil, position: nil)
		),
		("** You already requested that pack", .alreadyRequested),
		("** All Slots Full, Denied, You already have that item queued.", .alreadyRequested),
		("** Invalid Pack Number, Try Again", .invalidPack),
		(
			"** XDCC SEND denied, you must be on a known channel to request a pack",
			.denied("you must be on a known channel to request a pack")
		),
	] as [(String, XDCCBotMessage)])
	func reads(text: String, expected: XDCCBotMessage) {
		#expect(XDCCBotMessage.parse(text) == expected)
	}

	@Test("Other notices, and malformed ones, are not read", arguments: [
		"Hello there",
		"** Sending you pack #0 (\"zero.bin\"), which is 1KB.",
		"** Sending you pack #5, which is 1KB.",
		"** Added you to the main queue for pack 1000000 (\"big\") in position 1.",
		"** Closing Connection: Transfer Completed",
	])
	func ignores(text: String) {
		#expect(XDCCBotMessage.parse(text) == nil)
	}

	/// Some characters grow when lowercased, so a position found in a
	/// lowercased copy would not be a position in the notice itself.
	@Test("Characters that change length when lowercased do not throw positions off")
	func lengthChangingCase() {
		let dotted = String(repeating: "\u{0130}", count: 8)
		#expect(XDCCBotMessage.parse("** \(dotted) XDCC SEND denied, nope") == .denied("nope"))
		#expect(XDCCBotMessage.parse("** \(dotted) Added you to the main queue for pack 4 in position 2.")
			== .queued(pack: 4, filename: nil, position: 2))
	}

	@Test("A notice past the length cap is not read")
	func lengthCap() {
		let text = "** Invalid Pack Number, Try Again" + String(repeating: " ", count: XDCCBotMessage.maximumLength)
		#expect(XDCCBotMessage.parse(text) == nil)
	}
}
