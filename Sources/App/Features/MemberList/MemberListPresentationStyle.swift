/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

/** What a member row draws that its member does not carry.

 One read per invalidation, handed to every row. Each row used to ask the
 defaults store three times over — once for the glyph, once for its tooltip and
 once for the accessibility label — and every ask builds its own handle on the
 suite, on every row, on each rebuild a busy channel provokes. */
nonisolated struct MemberListPresentationStyle: Equatable, Sendable { // nonisolated: value
	/// Whether an IRC operator is drawn as one whatever the channel gave them.
	let favorsServerStaff: Bool
	/// "Use an x to indicate a user with no mode set", as the preference offers
	/// it: a rank column that is blank for most of a channel reads as unfinished
	/// to the readers who asked for the mark.
	let marksMembersWithNoMode: Bool
	private let badgeColors: [UserRank: Color]

	/// Reads the shared main-actor store, not a detached handle: this is
	/// asked once per invalidation, and a detached read builds its own handle
	/// on the defaults suite.
	@MainActor
	static func current() -> Self {
		var badgeColors: [UserRank: Color] = [:]
		for (rank, style) in MemberListRanks.ranked {
			guard let badge = style.badge else { continue }
			let color = GlasstualUserDefaults.container.color(for: badge.preferenceKey)
			guard color.alphaComponent > 0 else { continue }
			badgeColors[rank] = Color(nsColor: color)
		}

		return Self(
			favorsServerStaff: Preferences.Appearance.memberListSortFavorsServerStaff.value,
			marksMembersWithNoMode: Preferences.Appearance.memberListNoModeSymbol.value,
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
		let style = MemberListRanks.style(for: rank)
		guard style.symbolName == nil else { return style.symbolName }
		return marksMembersWithNoMode ? "xmark" : nil
	}

	func color(for rank: UserRank) -> Color {
		badgeColors[rank] ?? .secondary
	}
}
