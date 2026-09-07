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

	/// A value this Mac stored before its bound was declared is not the file's
	/// to answer for: a file that leaves the key alone still imports, and the
	/// stored value is left exactly as it was. A file that carries the value
	/// is held to the declaration like any other.
	@Test("A stored value outside its declared bounds does not block an import that leaves it alone")
	func storedOutOfRangeValuesDoNotBlockImports() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let limit = Preferences.Logging.scrollbackSaveLimit
		let joins = Preferences.Messages.showJoinLeave
		let store = fixture.stores.store(for: limit)
		store.set(50, forKey: limit.name)
		let session = fixture.session()

		let leavingItAlone = try PropertyListSerialization.data(
			fromPropertyList: [joins.name: false] as [String: Any], format: .xml, options: 0
		)
		try await session.prepareImport(from: fixture.write(leavingItAlone))
		#expect(session.errorMessage == nil, "\(session.errorMessage ?? "")")
		#expect(session.preview != nil)
		await session.commitPreview()
		#expect(session.errorMessage == nil, "\(session.errorMessage ?? "")")
		#expect(store.integer(forKey: limit.name) == 50)
		#expect(fixture.stores.store(for: joins).bool(forKey: joins.name) == false)

		let carryingIt = try PropertyListSerialization.data(
			fromPropertyList: [limit.name: 50] as [String: Any], format: .xml, options: 0
		)
		try await session.prepareImport(from: fixture.write(carryingIt))
		#expect(session.preview == nil)
		#expect(session.errorMessage != nil)
	}
}
