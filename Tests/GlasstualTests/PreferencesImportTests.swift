/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** What an imported file is allowed to say.

 Applying a configuration is `PreferencesTransferSession`'s job and is covered
 by `PreferencesTransferTests`. This is the gate in front of it: every value
 that arrives is answered for by the declaration that owns the name, by the
 family that owns the pattern when the name is made at runtime, or by nothing
 at all when the name belongs to somebody else's plugin. */
@Suite("Preference import validation")
@MainActor
struct PreferencesImportTests {
	private static let integerKey = Preferences.Logging.scrollbackSaveLimit
	private static let booleanKey = Preferences.Messages.showJoinLeave
	private static let excludedKey = Preferences.MainWindow.serverListSelection

	/// A hand-edited plist writes numbers and booleans as strings; the
	/// declaration is what says which of those are the same value.
	@Test("A value written as a string is coerced to the declared type")
	func stringsAreCoercedToTheDeclaredType() {
		#expect(Preferences.coerce("8765", forKey: Self.integerKey.name) == .integer(8765))
		#expect(Preferences.coerce("yes", forKey: Self.booleanKey.name) == .boolean(true))
	}

	@Test("A value the declaration cannot represent is refused")
	func unrepresentableValuesAreRefused() {
		#expect(Preferences.coerce(["not": "a number"], forKey: Self.integerKey.name) == nil)
		#expect(Preferences.coerce("banana", forKey: Self.integerKey.name) == nil)
		#expect(Preferences.coerce(["a", "b"], forKey: Self.booleanKey.name) == nil)
	}

	/// The bounds the Settings field has always enforced are declared on the
	/// key, so a file cannot write a count the field would refuse.
	@Test("A count outside the declared bounds is refused")
	func outOfRangeCountsAreRefused() {
		#expect(Preferences.coerce(99, forKey: Self.integerKey.name) == nil)
		#expect(Preferences.coerce(50001, forKey: Self.integerKey.name) == nil)
		#expect(Preferences.coerce(100, forKey: Self.integerKey.name) == .integer(100))
	}

	/** Window position, the selected row and the other restoration state are
	 excluded from an export because they describe this Mac rather than the
	 user's settings. Importing one would move somebody else's window state onto
	 this machine, so the same list is applied in both directions. */
	@Test("A key excluded from export is skipped on the way in")
	func excludedKeysAreSkipped() throws {
		#expect(Preferences.isExcludedFromExport(Self.excludedKey.name))
		#expect(Preferences.isExcludedFromExport(Self.integerKey.name) == false)

		let archive = try PreferencesArchive.decode(Self.encoded([
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
		let name = "Tests -> Import -> Unknown Plugin Key"
		let payload: PropertyListValue = ["anything": 1]

		#expect(Preferences.coerce(payload, forKey: name)?.dictionary?["anything"]?.integer == 1)
		#expect(Preferences.isExcludedFromExport(name))

		let archive = try PreferencesArchive.decode(Self.encoded([name: payload]))
		#expect(archive.values[name] == nil)
		#expect(archive.ignoredKeys.contains(name))
	}

	/** The per-event notification settings are named from an event and a
	 setting at the point of use, so no declaration lists them one by one. The
	 family is what says a sound is a string and everything else is a flag —
	 without it, a catalogued name was the one import path that accepted an
	 arbitrary property list. */
	@Test("A family-catalogued name is held to the shape its family declares")
	func familyCataloguedNamesAreCoerced() throws {
		let sound = NotificationEvent.highlight.preferenceKeyName(for: .sound)
		let flag = NotificationEvent.highlight.preferenceKeyName(for: .enabled)

		#expect(Preferences.coerce("Beep", forKey: sound) == .string("Beep"))
		#expect(Preferences.coerce("yes", forKey: flag) == .boolean(true))
		#expect(Preferences.coerce(["a", "b"], forKey: sound) == nil)
		#expect(Preferences.coerce(["nested": ["deeper": 1]], forKey: flag) == nil)
		#expect(Preferences.coerce(.data(Data("blob".utf8)), forKey: "NotificationType -> Made Up -> Setting") == nil)

		#expect(throws: PreferencesTransferError.self) {
			try PreferencesArchive.decode(Self.encoded([flag: ["nested": 1]]))
		}
	}

	/// A complete archive has to list every declared, exportable key, so the
	/// fixture fills in whatever the test itself does not care about.
	private static func encoded(_ values: [String: PropertyListValue]) throws -> Data {
		var preferences = values
		var unset: Set<String> = []
		for key in Preferences.allKeys
			where !Preferences.isExcludedFromExport(key.name)
			&& key.name != Preferences.Connection.clientList.name
			&& preferences[key.name] == nil
		{
			if let registered = key.registeredDefault {
				preferences[key.name] = registered
			} else {
				unset.insert(key.name)
			}
		}
		let document: [String: PropertyListValue] = [
			"format": .string(PreferencesArchive.format),
			"version": .integer(PreferencesArchive.version),
			"preferences": .dictionary(preferences),
			"unset": .array(unset.sorted().map(PropertyListValue.string)),
			"clients": .array([]),
		]
		return try PropertyListSerialization.data(
			fromPropertyList: document.propertyListObject, format: .xml, options: 0
		)
	}
}
