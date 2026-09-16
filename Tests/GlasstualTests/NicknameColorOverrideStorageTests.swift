/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

@Suite("Nickname colour overrides")
@MainActor
struct NicknameColorOverrideStorageTests {
	private static let defaultsKey = Preferences.Messages.nicknameColorStyleOverrides.name

	private func uniqueKey() -> String {
		"nickname-color-\(UUID().uuidString)".lowercased()
	}

	private func clear(_ key: String) {
		NicknameColors.setOverride(nil, for: key)
	}

	/// The value written is a plist dictionary, not an NSKeyedArchiver blob.
	@Test("Overrides are stored as readable components")
	func overrideIsStoredAsComponents() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = NSColor(srgbRed: 0.15, green: 0.35, blue: 0.75, alpha: 0.9)
		NicknameColors.setOverride(color, for: key)

		let overrides = try #require(GlasstualUserDefaults.container.dictionary(forKey: Self.defaultsKey))
		let stored = try #require(overrides[key] as? [String: Double])

		#expect(stored["red"] == 0.15)
		#expect(stored["alpha"] == 0.9)
	}

	/// Alpha used to survive because the value was an archived NSColor; it has
	/// to survive the component form too.
	@Test("A partly transparent colour keeps its alpha")
	func alphaSurvivesStorage() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = NSColor(srgbRed: 0.15, green: 0.35, blue: 0.75, alpha: 0.9)
		NicknameColors.setOverride(color, for: key)

		let stored = try #require(NicknameColors.pinnedColor(for: key))
		let components = try #require(NicknameColorComponents(stored))

		#expect(abs(components.alpha - 0.9) < 0.0001)
		#expect(abs(components.red - 0.15) < 0.0001)
	}

	/// Values written by earlier builds are archives; they still read back, so
	/// upgrading does not lose a user's pinned colours.
	@Test("A colour archived by an earlier build still reads back")
	func legacyArchiveIsStillReadable() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = try #require(NSColor.color(hexadecimal: "#2659BF"))
		let archive = try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)

		var overrides = GlasstualUserDefaults.container.dictionary(forKey: Self.defaultsKey) ?? [:]
		overrides[key] = archive
		GlasstualUserDefaults.container.set(overrides, forKey: Self.defaultsKey)

		let stored = try #require(NicknameColors.pinnedColor(for: key))
		#expect(stored.hexadecimalString == color.hexadecimalString)
	}

	@Test("Clearing an override removes it")
	func clearingRemovesTheOverride() throws {
		let key = uniqueKey()
		let color = try #require(NSColor.color(hexadecimal: "#2659BF"))

		NicknameColors.setOverride(color, for: key)
		clear(key)

		#expect(NicknameColors.pinnedColor(for: key) == nil)
	}

	@Test("A pinned colour is used for the nickname")
	func pinnedColorIsUsed() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = try #require(NSColor.color(hexadecimal: "#2659BF"))
		NicknameColors.setOverride(color, for: key)

		let pinned = NicknameColors.color(for: key)
		#expect(pinned.hexadecimalString == color.hexadecimalString)
	}

	@Test("Lookup is case-insensitive on the nickname")
	func lookupIsCaseInsensitive() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = try #require(NSColor.color(hexadecimal: "#2659BF"))
		NicknameColors.setOverride(color, for: key)

		#expect(
			NicknameColors.color(for: key.uppercased()).hexadecimalString ==
				color.hexadecimalString
		)
	}
}
