// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Server profiles")
struct UserProfileTests {
	@Test(
		"Invisible and directional characters never reach a display name",
		arguments: [
			"\u{200E}Ada\u{200F}", "A\u{200B}da", "Ada\u{FEFF}", "\u{2066}Ada\u{2069}", "Ada\u{E0041}",
			"\u{3164}Ada", "\u{02}Ada\u{02}", "\u{03}4Ada", "Ad\u{034F}a", "\u{FE0F}Ada",
		]
	)
	func invisibleCharactersAreRemoved(_ value: String) throws {
		#expect(try #require(ProfileDisplayName(wireValue: value)).text == "Ada")
	}

	@Test("A name made only of invisible characters is no name", arguments: ["", "   ", "\u{200B}\u{200D}", "\u{3164}\u{115F}"])
	func emptyNames(_ value: String) {
		#expect(ProfileDisplayName(wireValue: value) == nil)
	}

	@Test("Combining marks are capped per character, and spaces collapse")
	func combiningMarksAndSpaces() throws {
		let zalgo = "a" + String(repeating: "\u{0301}", count: 10)
		let name = try #require(ProfileDisplayName(wireValue: "\(zalgo)   b\n c"))

		#expect(name.text.unicodeScalars.count(where: { $0 == "\u{0301}" }) == 3)
		#expect(name.text.hasSuffix("b c"))
	}

	@Test("A long name is cut with an ellipsis, and an oversized value is dropped")
	func lengthLimits() throws {
		let long = try #require(ProfileDisplayName(wireValue: String(repeating: "x", count: 50)))

		#expect(long.text.count == 32)
		#expect(long.text.hasSuffix("…"))
		#expect(ProfileDisplayName(wireValue: String(repeating: "x", count: 1025)) == nil)
		#expect(ProfileDisplayName(wireValue: "Ada 🧪")?.text == "Ada 🧪")
	}

	@Test("Colours read with or without # and in either case", arguments: ["#80FF00", "80ff00"])
	func colors(_ value: String) throws {
		let color = try #require(ProfileColor(wireValue: value))

		#expect(color == ProfileColor(red: 0x80, green: 0xFF, blue: 0x00))
		#expect(color.hexString == "#80FF00")
	}

	@Test("A colour that is not six hex digits is refused", arguments: ["#FFF", "#GGGGGG", "1234567", "", "red"])
	func badColors(_ value: String) {
		#expect(ProfileColor(wireValue: value) == nil)
	}

	@Test("An avatar fills in its size and is a web address or nothing")
	func avatars() throws {
		let avatar = try #require(ProfileAvatar(wireValue: "https://example.org/a/{size}.png"))

		#expect(avatar.url(pixelSize: 64)?.absoluteString == "https://example.org/a/64.png")
		#expect(ProfileAvatar(wireValue: "javascript:alert(1)") == nil)
		#expect(ProfileAvatar(wireValue: "file:///etc/hosts") == nil)
		#expect(ProfileAvatar(wireValue: "https://example.org/" + String(repeating: "a", count: 2048)) == nil)
	}

	@Test("Applying a key reports whether the profile changed")
	func applying() {
		var profile = UserProfile()

		let first = profile.apply(key: "display-name", value: "Ada")
		let repeated = profile.apply(key: "display-name", value: "Ada")
		let unknown = profile.apply(key: "im.xmpp", value: "x")
		let color = profile.apply(key: "color", value: "#000000")
		let removal = profile.apply(key: "display-name", value: nil)

		#expect([first, repeated, unknown, color, removal] == [true, false, false, true, true])
		#expect(profile.displayName == nil)
		#expect(profile.isEmpty == false)
	}
}
