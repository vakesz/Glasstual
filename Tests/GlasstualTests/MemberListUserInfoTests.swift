/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
		#expect(content.awayStatus == MemberListStrings.userIsAway)
		#expect(content.privileges.contains("Operator"))
		#expect(content.privileges.contains(MemberListStrings.botCaption))
	}

	@Test("Missing identity fields use the feature-owned fallback labels")
	func contentUsesFallbackLabels() {
		let content = MemberListUserInfoContent(
			member: ChannelUser(user: User(nickname: "Guest")),
			privileges: ""
		)

		#expect(content.username == MemberListStrings.informationUnavailable)
		#expect(String(content.address.characters) == MemberListStrings.informationUnavailable)
		#expect(String(content.realName.characters) == MemberListStrings.informationUnavailable)
		#expect(content.account == MemberListStrings.notLoggedIn)
		#expect(content.awayStatus == MemberListStrings.userIsNotAway)
	}
}
