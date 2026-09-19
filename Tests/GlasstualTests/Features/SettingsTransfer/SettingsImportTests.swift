// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** What an imported file is allowed to say.

 Applying a configuration is `SettingsTransferSession`'s job and is covered
 by `SettingsTransferTests`. This is the gate in front of it: every value
 that arrives is answered for by the declaration that owns the name, by the
 family that owns the pattern when the name is made at runtime, or by nothing
 at all when the name is one nothing declares. */
@Suite("Settings import validation")
@MainActor
struct SettingsImportTests {
	private static let integerKey = SettingsKeys.Logging.scrollbackSaveLimit
	private static let booleanKey = SettingsKeys.Messages.showJoinLeave
	private static let excludedKey = SettingsKeys.MainWindow.sidebarSelection

	/// A hand-edited plist writes a number as a string; the declaration is what
	/// says that is the same value. A switch is not the same story: a boolean
	/// has to arrive as a boolean, so the string spellings `defaults write`
	/// accepts are refused rather than guessed at.
	@Test("A number written as a string is coerced, a boolean written as one is refused")
	func stringsAreCoercedToTheDeclaredType() {
		#expect(SettingsKeys.coerce("8765", forKey: Self.integerKey.name) == .integer(8765))
		#expect(SettingsKeys.coerce("yes", forKey: Self.booleanKey.name) == nil)
		#expect(SettingsKeys.coerce(true, forKey: Self.booleanKey.name) == .boolean(true))
	}

	@Test("A value the declaration cannot represent is refused")
	func unrepresentableValuesAreRefused() {
		#expect(SettingsKeys.coerce(["not": "a number"], forKey: Self.integerKey.name) == nil)
		#expect(SettingsKeys.coerce("banana", forKey: Self.integerKey.name) == nil)
		#expect(SettingsKeys.coerce(["a", "b"], forKey: Self.booleanKey.name) == nil)
	}

	/// The bounds the Settings field has always enforced are declared on the
	/// key, so a file cannot write a count the field would refuse.
	@Test("A count outside the declared bounds is refused")
	func outOfRangeCountsAreRefused() {
		#expect(SettingsKeys.coerce(99, forKey: Self.integerKey.name) == nil)
		#expect(SettingsKeys.coerce(50001, forKey: Self.integerKey.name) == nil)
		#expect(SettingsKeys.coerce(100, forKey: Self.integerKey.name) == .integer(100))
	}

	/** Window position, the selected row and the other restoration state are
	 excluded from an export because they describe this Mac rather than the
	 user's settings. Importing one would move somebody else's window state onto
	 this machine, so the same list is applied in both directions. */
	@Test("A key excluded from export is skipped on the way in")
	func excludedKeysAreSkipped() throws {
		#expect(SettingsKeys.isExcludedFromExport(Self.excludedKey.name))
		#expect(SettingsKeys.isExcludedFromExport(Self.integerKey.name) == false)

		let archive = try SettingsArchive.decode(Self.encoded([
			Self.excludedKey.name: "someone-elses-row",
			Self.integerKey.name: 2468,
		]))

		#expect(archive.values[Self.excludedKey.name] == nil)
		#expect(archive.ignoredKeys.contains(Self.excludedKey.name))
		/* The rest of the dictionary is imported all the same. */
		#expect(archive.values[Self.integerKey.name] == .integer(2468))
	}

	/** A name the catalogue does not cover belongs to somebody else, so there is
	 nothing here that could say what shape it should hold; it travels unchanged
	 rather than being rejected. A configuration file never carries one — an
	 uncatalogued name is excluded from export in both directions — but the
	 coercion has to be total for every caller that reaches it. */
	@Test("A key the catalogue does not know is left as it stands")
	func unknownKeysAreLeftUnchanged() throws {
		let name = "Tests -> Import -> Undeclared Key"
		let payload: PropertyListValue = ["anything": 1]

		#expect(SettingsKeys.coerce(payload, forKey: name)?.dictionary?["anything"]?.integer == 1)
		#expect(SettingsKeys.isExcludedFromExport(name))

		let archive = try SettingsArchive.decode(Self.encoded([name: payload]))
		#expect(archive.values[name] == nil)
		#expect(archive.ignoredKeys.contains(name))
	}

	/// A complete archive has to list every declared, exportable key, so the
	/// fixture fills in whatever the test itself does not care about.
	private static func encoded(_ values: [String: PropertyListValue]) throws -> Data {
		var settings = values
		var unset: Set<String> = []
		for key in SettingsKeys.allKeys
			where !SettingsKeys.isExcludedFromExport(key.name)
			&& key.name != SettingsKeys.Sessions.serverSessions.name
			&& settings[key.name] == nil
		{
			if let registered = key.registeredDefault {
				settings[key.name] = registered
			} else {
				unset.insert(key.name)
			}
		}
		let document: [String: PropertyListValue] = [
			"format": .string(SettingsArchive.format),
			"version": .integer(SettingsArchive.version),
			"preferences": .dictionary(settings),
			"unset": .array(unset.sorted().map(PropertyListValue.string)),
			"clients": .array([]),
		]
		return try PropertyListSerialization.data(
			fromPropertyList: document.propertyListObject, format: .xml, options: 0
		)
	}
}
