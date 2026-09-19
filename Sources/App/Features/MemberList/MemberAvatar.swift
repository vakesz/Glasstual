// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import SwiftUI

/// A nickname-derived avatar shared by member rows and user information.
struct MemberAvatar: View {
	let nickname: String
	let size: CGFloat
	/** The pinned colours as the list read them when it built this row.

	 Resolving a fill used to read the defaults store per avatar, which builds a
	 handle on the suite for every visible row and again on every rebuild a busy
	 channel provokes. The table cannot change while one list of rows is being
	 drawn, so the list reads it once and hands it down. A caller with no list
	 behind it -- the profile popover, a preview -- passes nothing and pays for
	 the one read it makes. */
	var overrides: NicknameColorOverrides?

	/** One lightness for every avatar, in both appearances.

	 The initial is drawn on the fill, not on the window, so the fill is what it
	 has to contrast with — and the transcript's lightness, which moves with the
	 appearance, says nothing about that. Fixing it low enough that white always
	 wins the luminance comparison keeps the letters the same colour down the
	 whole list. The clamped HSB fill this replaces left pale hues at about 2:1
	 under white initials. */
	private static let fillLightness = 0.45

	var body: some View {
		let fill = Self.fill(for: nickname, overrides: overrides)
		Circle()
			.fill(Color(nsColor: fill))
			.overlay {
				Text(Self.initial(for: nickname))
					.font(.system(size: round(size * 0.48), weight: .semibold))
					.foregroundStyle(Color(nsColor: fill.legibleForeground))
			}
			.frame(width: size, height: size)
	}

	/// A pinned colour is the user's to choose and stays what they chose;
	/// everything else takes the nickname's hue at the avatar's own lightness.
	static func fill(for nickname: String, overrides: NicknameColorOverrides? = nil) -> NSColor {
		if let pinned = NicknameColors.pinnedColor(for: nickname, in: overrides) {
			return pinned
		}

		return OKLCHColor(
			lightness: fillLightness,
			chroma: NicknameColors.chroma,
			hue: NicknameColors.hue(for: nickname)
		).nsColor
	}

	/** The first letter or digit of the nickname. Leading punctuation such
	 as the brackets and underscores IRC users decorate nicknames with is
	 skipped so that "[away]bob" still reads as "B". */
	private static func initial(for nickname: String) -> String {
		var initial: String?

		nickname.enumerateSubstrings(
			in: nickname.startIndex ..< nickname.endIndex,
			options: .byComposedCharacterSequences
		) { substring, _, _, stop in
			guard let substring else { return }

			if substring.rangeOfCharacter(from: .alphanumerics) != nil {
				initial = substring
				stop = true
			}
		}

		return (initial ?? String(nickname.prefix(1))).uppercased()
	}
}
