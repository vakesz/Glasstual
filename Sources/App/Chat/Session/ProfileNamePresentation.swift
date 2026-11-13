// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** When a display name someone set on the server may be drawn beside their
 nickname.

 A display name is presentation only and is never drawn or spoken without the
 nickname. On top of that, one that says nothing new or could pass for someone
 else is not shown at all: a name that compares equal to the person's own
 nickname, to another member's, to the local user's or to the network's
 services. The comparison folds compatibility forms, case, diacritics and
 width, then applies the server's casemapping. That is a best effort against
 look-alikes: Foundation offers no UTS #39 confusable skeletons. */
nonisolated enum ProfileNamePresentation {
	/// Names a display name may never take, whatever the channel holds.
	static let reservedNames = ["NickServ", "ChanServ"]

	/// The form two names are compared in.
	static func comparisonForm(_ name: String, casefold: (String) -> String) -> String {
		casefold(
			name.precomposedStringWithCompatibilityMapping
				.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
		)
	}

	/// The comparison forms of `nicknames` plus the local user's and the
	/// reserved names: the set ``displayName(for:nickname:collisions:casefold:)``
	/// checks against.
	static func collisionForms(
		nicknames: some Sequence<String>,
		localNickname: String,
		casefold: (String) -> String
	) -> Set<String> {
		var forms = Set(nicknames.map { comparisonForm($0, casefold: casefold) })
		forms.insert(comparisonForm(localNickname, casefold: casefold))
		for name in reservedNames {
			forms.insert(comparisonForm(name, casefold: casefold))
		}

		return forms
	}

	/// The display name to draw for `nickname`, or `nil` when there is none or
	/// it would be redundant or could be mistaken for another name.
	static func displayName(
		for profile: UserProfile,
		nickname: String,
		collisions: Set<String>,
		casefold: (String) -> String
	) -> String? {
		guard let name = profile.displayName?.text else { return nil }

		let form = comparisonForm(name, casefold: casefold)

		guard form != comparisonForm(nickname, casefold: casefold), collisions.contains(form) == false else {
			return nil
		}

		return name
	}
}
