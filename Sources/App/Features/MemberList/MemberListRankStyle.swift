/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/// Everything the member list knows about one rank.
///
/// The glyph, the badge colour preference, the privilege description and the
/// section header were four separate `switch`es over `UserRank`; a rank added
/// to one of them was easy to leave out of the other three.
nonisolated struct MemberListRankStyle: Sendable { // nonisolated: value
	/// The glyph the rank is drawn with. A member with no mode has none of its
	/// own: whether one is drawn at all is a preference.
	let symbolName: String?
	/// The badge colour preference that answers for the rank, where there is a
	/// badge to colour.
	let badge: UserListModeBadge?
	let privilegeDescription: LocalizedStringResource
	let sectionTitle: LocalizedStringResource
}

nonisolated enum MemberListRanks { // nonisolated: value
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
