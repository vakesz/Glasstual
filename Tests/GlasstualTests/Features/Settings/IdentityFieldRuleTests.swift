// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Identity field rule")
struct IdentityFieldRuleTests {
	@Test("An empty or blank entry restores the default of a required field")
	func blankEntryResets() {
		for rule in [IdentityFieldRule.nickname, .username, .realName] {
			#expect(rule.outcome(for: "") == .reset)
			#expect(rule.outcome(for: "  \t ") == .reset)
		}
	}

	@Test("An empty away nickname is stored as empty, since that means none")
	func emptyAwayNicknameIsStored() {
		#expect(IdentityFieldRule.optionalNickname.outcome(for: "") == .store(""))
		#expect(IdentityFieldRule.optionalNickname.outcome(for: "   ") == .store(""))
	}

	@Test("A nickname with a space or other characters a nickname cannot have is rejected")
	func invalidNicknameIsRejected() {
		#expect(IdentityFieldRule.nickname.outcome(for: "my nick") == .reject)
		#expect(IdentityFieldRule.nickname.outcome(for: "nick!user@host") == .reject)
		#expect(IdentityFieldRule.optionalNickname.outcome(for: "my nick") == .reject)
	}

	@Test("A valid nickname is stored without the whitespace around it")
	func validNicknameIsTrimmed() {
		#expect(IdentityFieldRule.nickname.outcome(for: "  alice ") == .store("alice"))
		#expect(IdentityFieldRule.optionalNickname.outcome(for: "alice_away") == .store("alice_away"))
	}

	@Test("A real name is one line of text, and a multi-line one is rejected")
	func realNameMustBeOneLine() {
		#expect(IdentityFieldRule.realName.outcome(for: " Alice Example ") == .store("Alice Example"))
		#expect(IdentityFieldRule.realName.outcome(for: "Alice\nExample") == .reject)
	}

	@Test("A username takes a normal value, trimmed")
	func usernameIsStored() {
		#expect(IdentityFieldRule.username.outcome(for: " glass ") == .store("glass"))
	}

	@Test("The field applies the outcome to the stored key")
	func fieldWritesThroughTheRule() {
		let settings = ObservableSettings.shared
		let key = SettingsKeys.Identity.nickname
		let original = settings[stored: key]
		defer { settings[stored: key] = original }

		let field = settings.identityField(for: key, rule: .nickname)

		#expect(field.write("  alice ") == true)
		#expect(field.text() == "alice")

		#expect(field.write("my nick") == false)
		#expect(field.text() == "alice")

		// The registered default is a generated "Guest" nickname, so it is not compared to a literal.
		#expect(field.write("") == true)
		#expect(field.text() != "alice")
		#expect(field.text().isHostmaskNickname)
	}
}
