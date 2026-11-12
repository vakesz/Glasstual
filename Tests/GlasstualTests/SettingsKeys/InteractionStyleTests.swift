// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** The one switch between dialogs and the conversation.

 Existing users never chose, so they read the registered default and keep the
 dialogs they had; nothing migrates them. The value is ordinary portable
 settings: catalogued, exported and imported with the rest. */
@Suite("Interaction style setting", .serialized)
@MainActor
struct InteractionStyleTests {
	private static let key = SettingsKeys.Interaction.style

	@Test("Dialogs are the default, so existing users keep what they had")
	func defaultsToDialogs() {
		#expect(Self.key.defaultValue == .dialogs)
		#expect(Self.key.registeredDefault == .integer(Int(InteractionStyle.dialogs.rawValue)))
	}

	@Test("The key is registered, catalogued and exported")
	func isCataloguedAndPortable() {
		#expect(SettingsKeys.key(named: Self.key.name) != nil)
		#expect(SettingsKeys.isCatalogued(Self.key.name))
		#expect(SettingsKeys.isExcludedFromExport(Self.key.name) == false)
	}

	@Test("An export carries the chosen style")
	func exportCarriesTheStyle() {
		let original = Self.key.storedValue
		defer { Self.key.storedValue = original }
		Self.key.value = .conversation

		let snapshot = SettingsArchive.snapshot(from: .live, sessions: [])

		#expect(snapshot.values[Self.key.name] == .integer(Int(InteractionStyle.conversation.rawValue)))
	}

	/// An archive written before the setting existed names it in neither list,
	/// and Merge leaves the local choice alone.
	@Test("Merging an older archive without the key keeps the current style")
	func olderArchiveLeavesTheValue() throws {
		var values: [String: PropertyListValue] = [:]
		var unset: [String] = []
		for key in SettingsKeys.allKeys
			where !SettingsKeys.isExcludedFromExport(key.name)
			&& key.name != SettingsKeys.Sessions.serverSessions.name
			&& key.name != Self.key.name
		{
			if let registered = key.registeredDefault {
				values[key.name] = registered
			} else {
				unset.append(key.name)
			}
		}
		let document: [String: PropertyListValue] = [
			"format": .string(SettingsArchive.format),
			"version": .integer(SettingsArchive.version),
			"preferences": .dictionary(values),
			"unset": .init(unset.sorted()),
			"clients": .array([]),
		]
		let data = try PropertyListSerialization.data(
			fromPropertyList: document.propertyListObject, format: .xml, options: 0
		)
		let archive = try SettingsArchive.decode(data)

		#expect(archive.values[Self.key.name] == nil)
		#expect(archive.unset.contains(Self.key.name) == false)
	}

	@Test("Every style has a picker label")
	func everyStyleHasALabel() {
		for style in InteractionStyle.allCases {
			#expect(String(localized: style.displayName).isEmpty == false)
		}
	}
}
