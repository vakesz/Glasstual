// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Configuration archives across key sets", .timeLimit(.minutes(1)))
struct PreferencesArchiveTests {
	private typealias Fixture = PreferencesTransferFixture

	/// The keys an archive written before them does not name, one registered
	/// and one unregistered, so both answers for "the file says nothing" run.
	private static let laterKeys = [Preferences.Messages.showJoinLeave.name, Preferences.Reactions.recent.name]

	/** Writes `archive` the way a build that predates `laterKeys` did: the
	 envelope is complete, but neither list names them. */
	private func olderKeySetDocument(
		_ archive: PreferencesArchive, source: PreferencesArchive.Source
	) throws -> Data {
		let data = try source == .localRecovery ? archive.recoveryEncoded() : archive.encoded()
		let object = try PropertyListSerialization.propertyList(from: data, format: nil)
		var root = try #require([String: PropertyListValue](propertyList: object))
		var preferences = try #require(root["preferences"]?.dictionary)
		var unset = try #require(root["unset"]?.stringArray)
		for name in Self.laterKeys {
			preferences.removeValue(forKey: name)
			unset.removeAll { $0 == name }
		}
		root["preferences"] = .dictionary(preferences)
		root["unset"] = PropertyListValue(unset)
		return try PropertyListSerialization.data(fromPropertyList: root.propertyListObject, format: .xml, options: 0)
	}

	/// Hands the older document to the session through the entry point its
	/// source uses: the import panel, or the protected recovery folder.
	private func prepare(
		_ data: Data, source: PreferencesArchive.Source, session: PreferencesTransferSession, fixture: Fixture
	) async throws {
		switch source {
		case .portable:
			try await session.prepareImport(from: fixture.write(data))
		case .localRecovery:
			let directory = await session.recoveryStore.directory
			let url = try PreferencesProtectedFolder(url: directory)
				.write(data, named: "Configuration-\(UUID().uuidString).plist")
			await session.prepareRecovery(PreferencesRecoveryBackup(url: url, created: Date()))
		}
	}

	@Test("An archive written before a key was declared still imports, and Merge keeps this Mac's value",
	      arguments: [PreferencesArchive.Source.portable, .localRecovery])
	func olderKeySetMergeLeavesLaterKeysAlone(source: PreferencesArchive.Source) async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		var archive = fixture.stores.snapshot(clients: [])
		archive.values[Preferences.Messages.showDateChanges.name] = false
		let data = try olderKeySetDocument(archive, source: source)

		fixture.stores.set(false, for: Preferences.Messages.showJoinLeave)
		fixture.stores.set(.array(["🎉"]), for: Preferences.Reactions.recent)
		let session = fixture.session()
		try await prepare(data, source: source, session: session, fixture: fixture)
		let preview = try #require(session.preview)
		#expect(preview.archive.source == source)

		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(fixture.stores[Preferences.Messages.showDateChanges] == false)
		#expect(fixture.stores[stored: Preferences.Messages.showJoinLeave] == false)
		#expect(fixture.stores[stored: Preferences.Reactions.recent] == ["🎉"])
	}

	@Test("Restoring an archive written before a key was declared returns that key to its registered default",
	      arguments: [PreferencesArchive.Source.portable, .localRecovery])
	func olderKeySetRestoreResetsLaterKeys(source: PreferencesArchive.Source) async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let data = try olderKeySetDocument(fixture.stores.snapshot(clients: []), source: source)

		fixture.stores.set(false, for: Preferences.Messages.showJoinLeave)
		fixture.stores.set(.array(["🎉"]), for: Preferences.Reactions.recent)
		let session = fixture.session()
		try await prepare(data, source: source, session: session, fixture: fixture)
		session.previewMode = .restore
		let plan = try #require(session.preview?.plan)
		#expect(Set(plan.changedKeys) == Set(Self.laterKeys))

		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(fixture.stores.persistedValue(for: Preferences.Messages.showJoinLeave) == nil)
		#expect(fixture.stores[Preferences.Messages.showJoinLeave] == Preferences.Messages.showJoinLeave.defaultValue)
		#expect(fixture.stores.persistedValue(for: Preferences.Reactions.recent) == nil)
	}

	@Test("Restore reports no change for a key this Mac already holds at its registered default")
	func restoreComparesEffectiveValues() throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let key = Preferences.Messages.showJoinLeave
		let current = fixture.stores.snapshot(clients: [])
		var archive = current
		archive.values.removeValue(forKey: key.name)
		let plan = try PreferencesTransferPlan(archive: archive, current: current, mode: .restore)
		#expect(plan.changedKeys.contains(key.name) == false)
	}

	/** A snapshot lists every unregistered key the source never wrote as
	 `unset`. Merging it must not read that as "delete this Mac's": the lists a
	 user builds up are exactly the unregistered keys. */
	@Test("Merge from a source that never created a list keeps the lists this Mac has")
	func mergeDoesNotApplyTheSourcesUnsetKeys() async throws {
		let source = try Fixture()
		let target = try Fixture()
		defer { source.cleanUp(); target.cleanUp() }
		let lists: [(any AnyPreferenceKey, PropertyListValue)] = [
			(Preferences.Rules.messageRules, .array([.dictionary(["uniqueIdentifier": "kept-filter"])])),
			(Preferences.Highlights.matchKeywords, .array([.dictionary(["string": "kept keyword"])])),
			(Preferences.LinkSchemes.permitted, .array(["kept-scheme"])),
			(Preferences.Input.tabCompletionSuffix, "kept, "),
			(Preferences.Reactions.recent, .array(["🎉"])),
		]
		for (key, value) in lists {
			target.stores.set(value, for: key)
		}
		source.stores.set(false, for: Preferences.Messages.showJoinLeave)
		let exported = try PreferencesArchive.decode(source.stores.snapshot(clients: []).encoded())
		for (key, _) in lists {
			#expect(exported.unset.contains(key.name))
		}

		let session = target.session()
		try await session.prepareImport(from: target.write(source.stores.snapshot(clients: []).encoded()))
		#expect(session.previewMode == .merge)
		#expect(session.preview?.plan?.removedKeys.isEmpty == true)
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(target.stores[stored: Preferences.Messages.showJoinLeave] == false)
		for (key, value) in lists {
			#expect(target.stores.persistedValue(for: key) == value)
		}
	}

	@Test("An archive value built in code claims no local-recovery privileges")
	func archivesDefaultToPortable() {
		let archive = PreferencesArchive(values: [:], unset: [], clients: [])
		#expect(archive.source == .portable)
		#expect(throws: PreferencesTransferError.self) { try archive.recoveryEncoded() }
	}
}
