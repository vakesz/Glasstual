// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Declared bounds on stored and imported preferences")
struct SettingsTransferBoundsTests {
	private typealias Fixture = SettingsTransferFixture

	/** A value stored before its bound was declared is not what a Settings
	 field would accept today, and every transfer path holds values to the
	 declarations. Launch clears such values back to their defaults, which is
	 what lets the recovery backup, an import and the field itself agree. A
	 file that carries the value is still refused. */
	@Test("A stored value outside its declared bounds is cleared at launch, so imports and backups proceed")
	func storedOutOfRangeValuesAreClearedAtLaunch() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let limit = SettingsKeys.Logging.scrollbackSaveLimit
		let start = SettingsKeys.FileTransfers.portRangeStart
		let end = SettingsKeys.FileTransfers.portRangeEnd
		let joins = SettingsKeys.Messages.showJoinLeave
		fixture.stores.store(for: limit).set(50, forKey: limit.name)
		fixture.stores.store(for: start).set(6000, forKey: start.name)
		fixture.stores.store(for: end).set(5000, forKey: end.name)
		fixture.stores.store(for: joins).set(true, forKey: joins.name)

		let repair = SettingsLaunchRepair.run(stores: fixture.stores, backupDirectory: fixture.directory)

		/* `object(forKey:)` answers out of the registration domain when nothing
		 is persisted, so what the scrub removed is read back off the persistent
		 domain instead. */
		#expect(repair.removed == [limit.name, start.name, end.name])
		#expect(repair.repaired.isEmpty)
		#expect(fixture.stores.persistedValue(for: limit) == nil)
		#expect(fixture.stores[limit] == limit.defaultValue)
		#expect(fixture.stores.persistedValue(for: start) == nil)
		#expect(fixture.stores[start] == start.defaultValue)
		#expect(fixture.stores.persistedValue(for: end) == nil)
		#expect(fixture.stores[end] == end.defaultValue)
		#expect(fixture.stores.persistedValue(for: joins) == true)
		#expect(SettingsLaunchRepair.run(stores: fixture.stores, backupDirectory: fixture.directory)
			== SettingsStoredValueRepair())

		let session = fixture.session()
		let sparse = SettingsArchive(values: [joins.name: false], unset: [], sessions: [])
		let sparseURL = try fixture.write(sparse.encoded())
		await session.prepareImport(from: sparseURL)
		#expect(session.errorMessage == nil)
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(session.result != nil)
		#expect(fixture.stores[stored: joins] == false)
		session.acknowledge()

		let carrying = SettingsArchive(values: [limit.name: 50], unset: [], sessions: [])
		let carryingURL = try fixture.write(carrying.encoded())
		await session.prepareImport(from: carryingURL)
		#expect(session.preview == nil)
		#expect(session.errorMessage != nil)
	}

	/** One bad element used to cost the whole collection. Launch now keeps
	 what the declaration still accepts, and writes the values it replaces to a
	 private file first. */
	@Test("Launch repair drops only the refused elements and fields, after backing up what was stored")
	func launchRepairKeepsAcceptedElements() throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let filters = SettingsKeys.Rules.messageRules
		let keywords = SettingsKeys.Highlights.matchKeywords
		let colors = SettingsKeys.Messages.nicknameColorStyleOverrides
		let storedFilters: PropertyListValue = .array([
			.dictionary(["uniqueIdentifier": "intact", "match": "spam", "fromTheFuture": "kept"]),
			.dictionary(["uniqueIdentifier": "one-bad-field", "match": "eggs", "ageComparator": 9]),
			.dictionary(["uniqueIdentifier": "intact", "match": "duplicate identifier"]),
			.dictionary(["uniqueIdentifier": "unknown-events", "events": .integer(6 | 1 << 20)]),
			"not a rule",
		])
		let storedKeywords: PropertyListValue = .array([.dictionary(["string": "kept"]), .integer(4)])
		let storedColors: PropertyListValue = .dictionary([
			"kept": .dictionary(["red": 1, "green": 0, "blue": 0, "alpha": 1]),
			"refused": .dictionary(["red": 7, "green": 0, "blue": 0, "alpha": 1]),
		])
		fixture.stores.set(storedFilters, for: filters)
		fixture.stores.set(storedKeywords, for: keywords)
		fixture.stores.set(storedColors, for: colors)

		let repair = SettingsLaunchRepair.run(stores: fixture.stores, backupDirectory: fixture.directory)

		#expect(repair.repaired == [filters.name, keywords.name, colors.name])
		#expect(repair.removed.isEmpty)
		let values = try #require(fixture.stores.persistedValue(for: filters)?.array)
		let rules = values.compactMap(\.dictionary)
		#expect(rules.map { $0["match"]?.string } == ["spam", "eggs", "duplicate identifier", nil])
		#expect(rules[0]["fromTheFuture"] == "kept")
		#expect(rules[1]["ageComparator"] == nil)
		#expect(rules[2]["uniqueIdentifier"] != "intact")
		#expect(rules[3]["events"] == .integer(6))
		#expect(fixture.stores[keywords] == [HighlightKeyword(string: "kept")])
		#expect(fixture.stores.persistedValue(for: colors)?.dictionary?.keys.sorted() == ["kept"])

		let backup = try #require(repair.backup)
		let permissions = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions]
		#expect((permissions as? NSNumber)?.intValue == 0o600)
		let saved = try PropertyListSerialization.propertyList(from: Data(contentsOf: backup), format: nil)
		let originals = try #require([String: PropertyListValue](propertyList: saved))
		#expect(originals == [filters.name: storedFilters, keywords.name: storedKeywords, colors.name: storedColors])
		#expect(SettingsLaunchRepair.run(stores: fixture.stores, backupDirectory: fixture.directory)
			== SettingsStoredValueRepair())
	}

	@Test("Launch repair changes nothing when the stored values cannot be backed up first")
	func launchRepairWithoutBackupChangesNothing() throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let limit = SettingsKeys.Logging.scrollbackSaveLimit
		fixture.stores.store(for: limit).set(50, forKey: limit.name)
		let blocked = try fixture.write(Data())

		let repair = SettingsLaunchRepair.run(stores: fixture.stores, backupDirectory: blocked)

		#expect(repair == SettingsStoredValueRepair())
		#expect(fixture.stores.persistedValue(for: limit) == 50)
	}
}
