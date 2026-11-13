// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// Which surface answers for the message a transfer ends with: the preview
/// sheet, or the window behind it once the sheet has closed.
@MainActor
@Suite("Settings transfer messages")
struct SettingsTransferMessageTests {
	@Test("A finished import leaves its outcome to the window, not to the closing preview sheet")
	func finishedImportIsNotThePreviewSheets() async throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let key = SettingsKeys.Logging.scrollbackSaveLimit
		let session = fixture.session()
		var imported = try session.liveSnapshot()
		imported.values[key.name] = 2000
		try await session.prepareImport(from: fixture.write(imported.encoded()))
		#expect(session.preview != nil)

		await session.commitPreview()

		#expect(session.result != nil)
		#expect(session.preview == nil)
		#expect(session.pendingMessage != nil)
		#expect(session.previewMessage == nil)
	}

	@Test("A failure that keeps the preview open is the preview sheet's to show")
	func failureWithOpenPreviewIsThePreviewSheets() async throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let key = SettingsKeys.Logging.scrollbackSaveLimit
		let session = fixture.session()
		var imported = try session.liveSnapshot()
		imported.values[key.name] = 2000
		try await session.prepareImport(from: fixture.write(imported.encoded()))
		fixture.stores.set(3200, for: key)

		await session.commitPreview()

		#expect(session.preview != nil)
		#expect(session.errorMessage == SettingsTransferError.stalePreview.localizedDescription)
		#expect(session.previewMessage == session.pendingMessage)
		#expect(session.previewMessage != nil)
	}
}
