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
		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(nil, forKey: key)
	}

	@Test("A pinned colour round-trips through the defaults store")
	func overrideRoundTrips() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = try #require(NSColor.textual_color(hexadecimalValue: "#2659BF"))
		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(color, forKey: key)

		let stored = try #require(UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: key))
		#expect(stored.textualHexadecimalValue == color.textualHexadecimalValue)
	}

	/// The value written is a plist dictionary, not an NSKeyedArchiver blob.
	@Test("Overrides are stored as readable components")
	func overrideIsStoredAsComponents() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = NSColor(srgbRed: 0.15, green: 0.35, blue: 0.75, alpha: 0.9)
		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(color, forKey: key)

		let overrides = try #require(TextualUserDefaults.container.dictionary(forKey: Self.defaultsKey))
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
		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(color, forKey: key)

		let stored = try #require(UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: key))
		let components = try #require(NicknameColorComponents(stored))

		#expect(abs(components.alpha - 0.9) < 0.0001)
		#expect(abs(components.red - 0.15) < 0.0001)
	}

	@Test("Components survive a Codable round trip")
	func componentsRoundTripThroughCodable() throws {
		let components = NicknameColorComponents(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
		let data = try JSONEncoder().encode(components)

		#expect(try JSONDecoder().decode(NicknameColorComponents.self, from: data) == components)
	}

	/// Values written by earlier builds are archives; they still read back, so
	/// upgrading does not lose a user's pinned colours.
	@Test("A colour archived by an earlier build still reads back")
	func legacyArchiveIsStillReadable() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = try #require(NSColor.textual_color(hexadecimalValue: "#2659BF"))
		let archive = try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)

		var overrides = TextualUserDefaults.container.dictionary(forKey: Self.defaultsKey) ?? [:]
		overrides[key] = archive
		TextualUserDefaults.container.set(overrides, forKey: Self.defaultsKey)

		let stored = try #require(UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: key))
		#expect(stored.textualHexadecimalValue == color.textualHexadecimalValue)
	}

	@Test("Clearing an override removes it")
	func clearingRemovesTheOverride() throws {
		let key = uniqueKey()
		let color = try #require(NSColor.textual_color(hexadecimalValue: "#2659BF"))

		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(color, forKey: key)
		clear(key)

		#expect(UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: key) == nil)
	}

	@Test("A pinned colour is used for the nickname")
	func pinnedColorIsUsed() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = try #require(NSColor.textual_color(hexadecimalValue: "#2659BF"))
		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(color, forKey: key)

		let pinned = UserNicknameColorStyleGenerator.color(for: key)
		#expect(pinned.textualHexadecimalValue == color.textualHexadecimalValue)
	}

	@Test("Lookup is case-insensitive on the nickname")
	func lookupIsCaseInsensitive() throws {
		let key = uniqueKey()
		defer { clear(key) }

		let color = try #require(NSColor.textual_color(hexadecimalValue: "#2659BF"))
		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(color, forKey: key)

		#expect(
			UserNicknameColorStyleGenerator.color(for: key.uppercased()).textualHexadecimalValue ==
				color.textualHexadecimalValue
		)
	}
}
