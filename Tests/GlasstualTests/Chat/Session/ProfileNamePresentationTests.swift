// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@Suite("When a display name is shown")
struct ProfileNamePresentationTests {
	private let fold: (String) -> String = { IRCCaseFolding.fold($0, using: .rfc1459) }

	private func shown(_ name: String, for nickname: String = "ada", members: [String] = ["bob"]) -> String? {
		var profile = UserProfile()
		profile.apply(key: "display-name", value: name)
		let collisions = ProfileNamePresentation.collisionForms(nicknames: members, localNickname: "me", casefold: fold)

		return ProfileNamePresentation.displayName(for: profile, nickname: nickname, collisions: collisions, casefold: fold)
	}

	@Test("A name that adds something is shown")
	func shownName() {
		#expect(shown("Ada Lovelace") == "Ada Lovelace")
	}

	@Test(
		"A name that repeats the nickname or passes for another is hidden",
		arguments: ["ADA", "Bob", "ｂｏｂ", "bób", "me", "NickServ", "chanserv", "{bob}"]
	)
	func hiddenNames(_ name: String) {
		let members = ["bob", "[bob]"]
		#expect(shown(name, members: members) == nil)
	}

	@Test("No profile, no name")
	func emptyProfile() {
		#expect(ProfileNamePresentation.displayName(for: UserProfile(), nickname: "ada", collisions: [], casefold: fold) == nil)
	}
}
