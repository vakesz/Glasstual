/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

/// The initial is drawn on the avatar, not on the window, so the fill is what
/// it has to be legible against. White letters on an HSB-clamped fill reached
/// about 2:1 for the pale hues.
@MainActor
@Suite("Member avatar contrast")
struct MemberListAvatarContrastTests {
	/** Generated names only: a real one could carry a pinned colour on the
	 machine running the tests, and a pinned colour is the user's to choose. */
	private let names = (0 ..< 400).map { "generated-avatar-\($0)" }

	@Test("Every initial clears WCAG's ratio for text on its own avatar")
	func initialsContrastWithTheirFill() {
		for name in names {
			let fill = MemberAvatar.fill(for: name)
			let ratio = MemberAvatar.initialColor(on: fill).contrastRatio(against: fill)
			#expect(ratio >= 4.5, "\(name): \(ratio)")
		}
	}

	/// The transcript's nickname colour moves with the appearance because it is
	/// drawn on the transcript's ground. The avatar carries its own ground, so
	/// one fill answers for both appearances — and it has to answer well.
	@Test("The avatar's fill is one colour for both appearances")
	func fillDoesNotFollowTheAppearance() {
		for name in names.prefix(50) {
			let dark = UserNicknameColorStyleGenerator.color(for: name, isDark: true)
			let light = UserNicknameColorStyleGenerator.color(for: name, isDark: false)
			#expect(dark.textualHexadecimalValue != light.textualHexadecimalValue)

			let fill = MemberAvatar.fill(for: name)
			#expect(MemberAvatar.fill(for: name.uppercased()).textualHexadecimalValue
				== fill.textualHexadecimalValue)
			#expect(fill.textualHexadecimalValue != dark.textualHexadecimalValue)
			#expect(MemberAvatar.initialColor(on: fill).contrastRatio(against: fill) >= 4.5)
		}
	}

	/// A pinned colour is the reader's own and is drawn as chosen, so the
	/// letters have to move instead: black on a pale pin, white on a dark one.
	@Test("A pinned colour still gets a readable initial")
	func pinnedColoursGetAReadableInitial() {
		let pins = [
			NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
			NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
			NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1),
			NSColor(srgbRed: 0.98, green: 0.92, blue: 0.2, alpha: 1),
			NSColor(srgbRed: 0.1, green: 0.1, blue: 0.6, alpha: 1),
		]
		let nickname = "pinned-avatar-\(UUID().uuidString.lowercased())"
		let previous = UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: nickname)
		defer { UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(previous, forKey: nickname) }

		for pin in pins {
			UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(pin, forKey: nickname)
			let fill = MemberAvatar.fill(for: nickname)
			#expect(fill.textualHexadecimalValue == pin.textualHexadecimalValue)
			let ratio = MemberAvatar.initialColor(on: fill).contrastRatio(against: fill)
			#expect(ratio >= 4.5, "\(pin): \(ratio)")
		}
	}
}
