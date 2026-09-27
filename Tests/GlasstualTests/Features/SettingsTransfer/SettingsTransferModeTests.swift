// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
@testable import Glasstual
import Testing

@MainActor
@Suite("Settings transfer mode validation")
struct SettingsTransferModeTests {
	@Test("A sparse import remains available when only one mode has a valid port range",
	      arguments: [SettingsTransferMode.merge, .restore])
	func validModeCanBePreviewedAndCommitted(_ validMode: SettingsTransferMode) async throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let start = SettingsKeys.FileTransfers.portRangeStart
		let end = SettingsKeys.FileTransfers.portRangeEnd
		fixture.stores.set(5000, for: start)
		fixture.stores.set(5100, for: end)
		let imported: [String: PropertyListValue] = validMode == .merge
			? [start.name: 5050]
			: [end.name: 1200]
		let archive = SettingsArchive(values: imported, unset: [], sessions: [])
		let url = try fixture.write(archive.encoded())
		let session = fixture.session()

		await session.prepareImport(from: url)

		#expect(session.errorMessage == nil)
		let preview = try #require(session.preview)
		#expect(preview.mode == validMode)
		#expect(preview.supports(validMode))
		let invalidMode: SettingsTransferMode = validMode == .merge ? .restore : .merge
		#expect(preview.supports(invalidMode) == false)
		#expect(preview.plan != nil)
		session.previewMode = invalidMode
		#expect(session.previewMode == validMode)

		await session.commitPreview()

		#expect(session.errorMessage == nil)
		#expect(session.result != nil)
		#expect(fixture.stores[start] == (validMode == .merge ? 5050 : start.defaultValue))
		#expect(fixture.stores[end] == (validMode == .merge ? 5100 : 1200))
	}
}
