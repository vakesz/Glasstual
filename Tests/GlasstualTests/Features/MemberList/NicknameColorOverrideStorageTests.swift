// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
@testable import Glasstual
import Testing

@Suite("Nickname colour overrides")
@MainActor
struct NicknameColorOverrideStorageTests {
	private static let defaultsKey = SettingsKeys.Messages.nicknameColorStyleOverrides.name

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

	/// Alpha is one of the four stored components, so a partly transparent
	/// colour has to come back as one.
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

	/// Components are the only stored shape there is a reader for. An archive --
	/// what a pre-2.0 build wrote, or what a hand-edited plist can hold -- reads
	/// as no override rather than as an unarchiving attempt.
	@Test("An archived colour reads as no override")
	func archivedColorIsNotAnOverride() throws {
		let key = uniqueKey()
		defer {
			var overrides = GlasstualUserDefaults.container.dictionary(forKey: Self.defaultsKey) ?? [:]
			overrides.removeValue(forKey: key)
			GlasstualUserDefaults.container.set(overrides.isEmpty ? nil : overrides, forKey: Self.defaultsKey)
		}

		let color = try #require(NSColor.color(hexadecimal: "#2659BF"))
		let archive = try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)

		var overrides = GlasstualUserDefaults.container.dictionary(forKey: Self.defaultsKey) ?? [:]
		overrides[key] = archive
		GlasstualUserDefaults.container.set(overrides, forKey: Self.defaultsKey)

		#expect(NicknameColors.pinnedColor(for: key) == nil)
		#expect(NicknameColors.color(for: key, isDark: true) == NicknameColors.generatedColor(for: key, isDark: true))
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
