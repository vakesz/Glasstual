// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

/// A colour chosen on the server is relit, so no server can make a name
/// invisible or match the ground it is drawn on.
@MainActor
@Suite("Server profile colours")
struct ProfileColorTests {
	private nonisolated static let extremes = ["#000000", "#FFFFFF", "#FFFF00", "#0000FF", "#FF0000"]

	@Test("A chosen colour reads against both transcript grounds", arguments: extremes)
	func transcriptContrast(_ hex: String) throws {
		let profileColor = try #require(ProfileColor(wireValue: hex))
		let palette = TranscriptTheme.defaultPalette

		for isDark in [false, true] {
			let ground = isDark ? palette.background.dark.color : palette.background.light.color
			let color = NicknameColors.color(for: "generated-profile", profileColor: profileColor, isDark: isDark)
			#expect(color.contrastRatio(against: ground) >= 4.5, "\(hex) on \(isDark ? "dark" : "light")")
		}
	}

	@Test("A chosen colour gives the avatar a readable initial", arguments: extremes)
	func avatarContrast(_ hex: String) throws {
		let profileColor = try #require(ProfileColor(wireValue: hex))
		let fill = MemberAvatar.fill(for: "generated-profile", profileColor: profileColor)

		#expect(fill.legibleForeground.contrastRatio(against: fill) >= 4.5)
	}

	@Test("A pinned colour wins over a chosen one, which wins over the hash")
	func precedence() throws {
		let nickname = "profile-\(UUID().uuidString.lowercased())"
		let chosen = try #require(ProfileColor(wireValue: "#2060C0"))
		let hashed = NicknameColors.color(for: nickname, isDark: false)
		let relit = NicknameColors.color(for: nickname, profileColor: chosen, isDark: false)
		#expect(relit.hexadecimalString != hashed.hexadecimalString)

		let previous = NicknameColors.pinnedColor(for: nickname)
		let pinned = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
		NicknameColors.setOverride(pinned, for: nickname)
		defer { NicknameColors.setOverride(previous, for: nickname) }
		#expect(NicknameColors.color(for: nickname, profileColor: chosen, isDark: false).hexadecimalString
			== pinned.hexadecimalString)
	}

	@Test("Converting to OKLCH keeps the hue of a primary")
	func oklchRoundTrip() {
		let blue = OKLCHColor(red: 0, green: 0, blue: 255)

		#expect(abs(blue.hue - 264) < 2)
		#expect(abs(blue.lightness - 0.452) < 0.01)
	}
}
