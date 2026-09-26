// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Holds each read until the test chooses its completion order, including
/// reads whose underlying I/O does not respond to task cancellation.
private actor ThemeDocumentReads {
	private var pending: [URL: CheckedContinuation<Data, any Error>] = [:]
	private var started: [URL: CheckedContinuation<Void, Never>] = [:]

	func read(_ url: URL) async throws -> Data {
		try await withCheckedThrowingContinuation { continuation in
			pending[url] = continuation
			started.removeValue(forKey: url)?.resume()
		}
	}

	func waitForRead(_ url: URL) async {
		guard pending[url] == nil else { return }
		await withCheckedContinuation { started[url] = $0 }
	}

	func finish(_ url: URL, with result: Result<Data, any Error>) {
		pending.removeValue(forKey: url)?.resume(with: result)
	}
}

@MainActor
@Suite("Settings theme import ownership", .timeLimit(.minutes(1)))
struct SettingsThemeImportTests {
	@Test("A superseded read cannot replace the newer theme or report a stale failure", arguments: [false, true])
	func supersededReadIsIgnored(fails: Bool) async throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let reads = ThemeDocumentReads()
		let store = ThemeStore(stores: fixture.stores)
		let model = SettingsModel(themeStore: store, readThemeDocument: { try await reads.read($0) })
		let firstURL = URL(filePath: "/first.plist")
		let secondURL = URL(filePath: "/second.plist")
		model.completeImport(.success(firstURL), request: .transcriptTheme)
		let first = try #require(model.themeImportTask)
		await reads.waitForRead(firstURL)
		model.completeImport(.success(secondURL), request: .transcriptTheme)
		let second = try #require(model.themeImportTask)
		await reads.waitForRead(secondURL)
		var newer = TranscriptTheme.bubbles
		newer.name = "Latest choice"
		try await reads.finish(secondURL, with: .success(PropertyListEncoder().encode(newer)))
		await second.value
		#expect(store.theme == newer)
		#expect(first.isCancelled)
		#expect(model.themeImportTask == nil)

		let result: Result<Data, any Error> = try fails
			? .failure(CocoaError(.fileReadCorruptFile))
			: .success(PropertyListEncoder().encode(TranscriptTheme.lines))
		await reads.finish(firstURL, with: result)
		await first.value
		#expect(store.theme == newer)
		#expect(model.presentationFailure == nil)
	}

	@Test("Closing Settings or resetting the theme cancels a pending import", arguments: [false, true])
	func cancelledImportDoesNotApply(reset: Bool) async throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let reads = ThemeDocumentReads()
		let store = ThemeStore(stores: fixture.stores)
		let model = SettingsModel(themeStore: store, readThemeDocument: { try await reads.read($0) })
		let url = URL(filePath: "/pending.plist")
		model.completeImport(.success(url), request: .transcriptTheme)
		let task = try #require(model.themeImportTask)
		await reads.waitForRead(url)
		if reset {
			model.resetTranscriptTheme()
		} else {
			model.deactivate()
		}
		let expected = store.theme
		try await reads.finish(url, with: .success(PropertyListEncoder().encode(TranscriptTheme.bubbles)))
		await task.value
		#expect(task.isCancelled)
		#expect(model.themeImportTask == nil)
		#expect(store.theme == expected)
		#expect(model.presentationFailure == nil)
	}
}
