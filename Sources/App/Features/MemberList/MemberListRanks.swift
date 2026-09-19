// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/** What a member row draws that its member does not carry.

 One read per invalidation, handed to every row. Each row used to ask the
 defaults store three times over — once for the glyph, once for its tooltip and
 once for the accessibility label — and every ask builds its own handle on the
 suite, on every row, on each rebuild a busy channel provokes. */
nonisolated struct MemberListPresentationStyle: Equatable, Sendable {
	/// Whether an IRC operator is drawn as one whatever the channel gave them.
	let favorsServerStaff: Bool
	private let badgeColors: [UserRank: Color]

	/// Reads the shared main-actor store, not a detached handle: this is
	/// asked once per invalidation, and a detached read builds its own handle
	/// on the defaults suite.
	@MainActor
	static func current() -> Self {
		var badgeColors: [UserRank: Color] = [:]
		for (rank, style) in MemberListRanks.ranked {
			guard let badge = style.badge else { continue }
			let color = GlasstualUserDefaults.container.color(for: badge.settingsKey)
			guard color.alphaComponent > 0 else { continue }
			badgeColors[rank] = Color(nsColor: color)
		}

		return Self(
			favorsServerStaff: SettingsKeys.Appearance.memberListSortFavorsServerStaff.value,
			badgeColors: badgeColors
		)
	}

	/** The rank a row stands for.

	 One answer for the glyph, the tooltip, the accessibility label and the
	 profile: with server staff sorted to the top, an IRC operator is drawn as
	 one whatever the channel gave them, and a label that named the channel rank
	 instead disagreed with the glyph beside it. */
	func displayRank(isIRCOperator: Bool, channelRank: UserRank) -> UserRank {
		isIRCOperator && favorsServerStaff ? .irCopByMode : channelRank
	}

	func symbolName(for rank: UserRank) -> String? {
		MemberListRanks.style(for: rank).symbolName
	}

	func color(for rank: UserRank) -> Color {
		badgeColors[rank] ?? .secondary
	}
}

/// Everything the member list knows about one rank.
///
/// The glyph, the badge colour setting, the privilege description and the
/// section header were four separate `switch`es over `UserRank`; a rank added
/// to one of them was easy to leave out of the other three.
nonisolated struct MemberListRankStyle: Sendable {
	/// Only an actual privilege gets a glyph; an ordinary member has none.
	let symbolName: String?
	/// The badge colour setting that answers for the rank, where there is a
	/// badge to colour.
	let badge: UserListModeBadge?
	let privilegeDescription: LocalizedStringResource
	let sectionTitle: LocalizedStringResource
}

nonisolated enum MemberListRanks {
	/// What a member with no mode at all is called and grouped under.
	static let unranked = MemberListRankStyle(
		symbolName: nil,
		badge: nil,
		privilegeDescription: .MemberList.privilegeNone,
		sectionTitle: .MemberList.sectionMembers
	)

	static func style(for rank: UserRank) -> MemberListRankStyle {
		ranked[rank] ?? unranked
	}

	/// What a rank is called where a row, a tooltip or a profile names it.
	static func privilegeDescription(for rank: UserRank) -> String {
		String(localized: style(for: rank).privilegeDescription)
	}

	/// The rank one member is drawn as, outside the list: there is one member to
	/// draw rather than a column of them, so there is no snapshot in hand and
	/// the current one is read for them.
	@MainActor
	static func displayRank(for member: Member) -> UserRank {
		MemberListPresentationStyle.current()
			.displayRank(isIRCOperator: member.user.isIRCop, channelRank: member.rank)
	}

	/// The same for what that member's rank is called.
	@MainActor
	static func privilegeDescription(for member: Member) -> String {
		privilegeDescription(for: displayRank(for: member))
	}

	/// What the group of members holding a rank is headed with.
	static func sectionTitle(for rank: UserRank) -> String {
		String(localized: style(for: rank).sectionTitle)
	}

	/// Every rank that carries a badge of its own.
	static let ranked: [UserRank: MemberListRankStyle] = [
		.irCopByMode: MemberListRankStyle(
			symbolName: "checkmark.shield.fill",
			badge: .ircOperator,
			privilegeDescription: .MemberList.rankServerStaff,
			sectionTitle: .MemberList.rankServerStaff
		),
		.channelOwner: MemberListRankStyle(
			symbolName: "crown.fill",
			badge: .channelOwner,
			privilegeDescription: .MemberList.privilegeChannelOwner,
			sectionTitle: .MemberList.sectionOwners
		),
		.superOperator: MemberListRankStyle(
			symbolName: "star.fill",
			badge: .superOperator,
			privilegeDescription: .MemberList.privilegeAdmin,
			sectionTitle: .MemberList.sectionAdmins
		),
		.normalOperator: MemberListRankStyle(
			symbolName: "shield.fill",
			badge: .normalOperator,
			privilegeDescription: .MemberList.privilegeOperator,
			sectionTitle: .MemberList.sectionOperators
		),
		.halfOperator: MemberListRankStyle(
			symbolName: "shield.lefthalf.filled",
			badge: .halfOperator,
			privilegeDescription: .MemberList.privilegeHalfOperator,
			sectionTitle: .MemberList.sectionHalfOperators
		),
		.voiced: MemberListRankStyle(
			symbolName: "mic.fill",
			badge: .voiced,
			privilegeDescription: .MemberList.privilegeVoice,
			sectionTitle: .MemberList.sectionVoiced
		),
	]
}
