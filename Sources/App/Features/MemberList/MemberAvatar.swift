/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import SwiftUI

/// A nickname-derived avatar shared by member rows and user information.
struct MemberAvatar: View {
	let nickname: String
	let size: CGFloat

	private static let maximumBrightness: CGFloat = 0.72
	private static let minimumSaturation: CGFloat = 0.45

	var body: some View {
		Circle()
			.fill(Color(nsColor: Self.color(for: nickname)))
			.overlay {
				Text(Self.initial(for: nickname))
					.font(.system(size: round(size * 0.48), weight: .semibold))
					.foregroundStyle(.white)
			}
			.frame(width: size, height: size)
	}

	private static func color(for nickname: String) -> NSColor {
		var color = UserNicknameColorStyleGenerator.color(for: nickname)
		color = color.usingColorSpace(.sRGB) ?? color

		var hue: CGFloat = 0
		var saturation: CGFloat = 0
		var brightness: CGFloat = 0
		color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

		brightness = min(brightness, maximumBrightness)
		saturation = max(saturation, minimumSaturation)
		return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
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
