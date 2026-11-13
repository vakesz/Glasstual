// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct SettingsTransferExportTests {
	private typealias Fixture = SettingsTransferFixture

	@Test("An export owns the workflow until its Save panel completes")
	func exportOwnsWorkflowUntilCompletion() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let data = try await session.exportData()
		let url = try fixture.write(data)
		#expect(!session.canStart)
		await #expect(throws: SettingsTransferError.self) { try await session.exportData() }
		session.cancelPreview()
		await session.prepareImport(from: url)
		#expect(session.preview == nil)
		session.completeExport(.success(url))
		#expect(session.canStart)
		#expect(session.completionMessage != nil)
	}

	@Test("Cancelling the Save panel releases its workflow without a message")
	func cancelledExportReleasesWorkflow() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		_ = try await session.exportData()
		#expect(!session.canStart)
		session.completeExport(.failure(CocoaError(.userCancelled)))
		#expect(session.canStart)
		#expect(session.errorMessage == nil)
		#expect(session.completionMessage == nil)
	}

	@Test("A second transfer's busy result cannot release an active export")
	func busyErrorPreservesExport() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		_ = try await session.exportData()
		session.report(SettingsTransferError.busy)
		#expect(!session.canStart)
		#expect(session.errorMessage == nil)
		session.completeExport(.failure(CocoaError(.userCancelled)))
		#expect(session.canStart)
	}

	@Test("A backup-list failure cannot replace an active export")
	func backupFailurePreservesExport() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let invalidDirectory = try fixture.write(Data())
		let session = fixture.session(backupDirectory: invalidDirectory)
		_ = try await session.exportData()
		await session.refreshBackups()
		#expect(!session.canStart)
		#expect(session.errorMessage == nil)
		session.completeExport(.success(invalidDirectory))
		#expect(session.completionMessage != nil)
	}

	@Test("An export completion cannot discard an import preview")
	func unrelatedExportCompletionPreservesPreview() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		let url = try fixture.write(session.liveSnapshot().encoded())
		await session.prepareImport(from: url)
		let preview = try #require(session.preview)
		session.completeExport(.success(url))
		#expect(session.preview?.id == preview.id)
		#expect(session.completionMessage == nil)
	}

	@Test("Export failure is visible and user cancellation stays quiet")
	func exportErrorsAreVisible() async throws {
		let fixture = try Fixture()
		defer { fixture.cleanUp() }
		let session = fixture.session()
		_ = try await session.exportData()
		session.completeExport(.failure(CocoaError(.fileWriteNoPermission)))
		#expect(session.errorMessage != nil)
		#expect(session.completionMessage == nil)
		session.acknowledge()
		_ = try await session.exportData()
		session.completeExport(.failure(CocoaError(.userCancelled)))
		#expect(session.errorMessage == nil)
	}
}
