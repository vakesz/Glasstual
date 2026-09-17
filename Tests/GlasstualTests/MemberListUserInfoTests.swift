// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Member list user information")
struct MemberListUserInfoTests {
	@Test("Available user fields are presented without changing their meaning")
	func contentPresentsAvailableFields() {
		var user = User(nickname: "Ada")
		user.username = "ada"
		user.address = "example.test"
		user.realName = "Ada Lovelace"
		user.account = "ada-account"
		user.isAway = true
		user.isBot = true

		let content = MemberListUserInfoContent(
			member: ChannelUser(user: user),
			privileges: "Operator"
		)

		#expect(content.nickname == "Ada")
		#expect(content.username == "ada")
		#expect(String(content.address.characters) == "example.test")
		#expect(String(content.realName.characters) == "Ada Lovelace")
		#expect(content.account == "ada-account")
		#expect(content.awayStatus == MemberListUserInfoContent.awayStatus(isAway: true))
		#expect(content.privileges == "Operator (\(String(localized: .MemberList.botCaption)))")
	}

	@Test("Missing identity fields use the feature-owned fallback labels")
	func contentUsesFallbackLabels() {
		let content = MemberListUserInfoContent(
			member: ChannelUser(user: User(nickname: "Guest")),
			privileges: ""
		)

		#expect(content.username == String(localized: .MemberList.informationUnavailable))
		#expect(String(content.address.characters) == String(localized: .MemberList.informationUnavailable))
		#expect(String(content.realName.characters) == String(localized: .MemberList.informationUnavailable))
		#expect(content.account == String(localized: .MemberList.notLoggedIn))
		#expect(content.awayStatus == MemberListUserInfoContent.awayStatus(isAway: false))
	}

	/** The Status row used to read "User is away", a sentence about a person
	 answering a label that already names them. The sentence forms stay: they
	 are what VoiceOver reads out of a member-list row, where "Away" on its own
	 has nothing to attach itself to. */
	@Test("The profile states a status; the row speaks a sentence")
	func awayStatusReadsAsAValueInTheProfile() {
		#expect(MemberListUserInfoContent.awayStatus(isAway: true) == "Away")
		#expect(MemberListUserInfoContent.awayStatus(isAway: false) == "Available")
		#expect(String(localized: .MemberList.userIsAway) == "User is away")
		#expect(String(localized: .MemberList.userIsNotAway) == "User is not away")
	}

	/// An empty row is empty, not broken: "Information Not Available" was a
	/// sentence of apology in a column of one-word values.
	@Test("A field the server never sent is an em dash")
	func unavailableInformationIsAnEmDash() {
		#expect(String(localized: .MemberList.informationUnavailable) == "—")
	}
}
