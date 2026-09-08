/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import GlasstualPluginKit
import SwiftUI
import Testing

@MainActor
struct PreferencesTransferBoundsTests {
	private typealias Fixture = PreferencesTransferFixture

	/** A value stored before its bound was declared is not what a Settings
	 field would accept today, and every transfer path holds values to the
	 declarations. Launch clears such values back to their defaults, which is
	 what lets the recovery backup, an import and the field itself agree. A
	 file that carries the value is still refused. */
	@Test("A stored value outside its declared bounds is cleared at launch, so imports and backups proceed")
	func storedOutOfRangeValuesAreClearedAtLaunch() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let limit = Preferences.Logging.scrollbackSaveLimit
		let start = Preferences.FileTransfers.portRangeStart
		let end = Preferences.FileTransfers.portRangeEnd
		let joins = Preferences.Messages.showJoinLeave
		fixture.stores.store(for: limit).set(50, forKey: limit.name)
		fixture.stores.store(for: start).set(6000, forKey: start.name)
		fixture.stores.store(for: end).set(5000, forKey: end.name)
		fixture.stores.store(for: joins).set(true, forKey: joins.name)

		let refused = fixture.stores.removeValuesDeclarationsRefuse()

		/* `object(forKey:)` answers out of the registration domain when nothing
		 is persisted, so what the scrub removed is read back off the persistent
		 domain instead. */
		#expect(Set(refused) == [limit.name, start.name, end.name])
		#expect(fixture.stores.persistedValue(for: limit) == nil)
		#expect(fixture.stores[limit] == limit.defaultValue)
		#expect(fixture.stores.persistedValue(for: start) == nil)
		#expect(fixture.stores[start] == start.defaultValue)
		#expect(fixture.stores.persistedValue(for: end) == nil)
		#expect(fixture.stores[end] == end.defaultValue)
		#expect(fixture.stores.persistedValue(for: joins) == true)
		#expect(fixture.stores.removeValuesDeclarationsRefuse().isEmpty)

		let session = fixture.session()
		let sparse = try PropertyListSerialization.data(
			fromPropertyList: [joins.name: false] as [String: Any], format: .xml, options: 0
		)
		let sparseURL = try fixture.write(sparse)
		await session.prepareImport(from: sparseURL)
		#expect(session.errorMessage == nil)
		await session.commitPreview()
		#expect(session.errorMessage == nil)
		#expect(session.result != nil)
		#expect(fixture.stores[stored: joins] == false)
		session.acknowledge()

		let carrying = try PropertyListSerialization.data(
			fromPropertyList: [limit.name: 50] as [String: Any], format: .xml, options: 0
		)
		let carryingURL = try fixture.write(carrying)
		await session.prepareImport(from: carryingURL)
		#expect(session.preview == nil)
		#expect(session.errorMessage != nil)
	}
}
