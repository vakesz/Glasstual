/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Preferences pane catalog and file requests")
struct PreferencesSessionTests {
	private static let importFailure = NSError(
		domain: "PreferencesSessionTests", code: 1,
		userInfo: [NSLocalizedDescriptionKey: "Import failed"]
	)

	private static let cancellation = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)

	@Test("File importer dismissal retains the request until its completion is applied")
	func importCompletionSurvivesDismissal() throws {
		let model = PreferencesPaneModel()
		var pending = PendingFileRequest<PreferencesImportRequest>()
		pending.present(.transcriptTheme)
		let request = try #require(pending.request)
		pending.dismiss(request.id)
		#expect(!pending.isPresented)
		#expect(pending.request?.kind == .transcriptTheme)
		let completed = pending.complete(request.id)
		let kind = try #require(completed)
		model.completeImport(.failure(Self.importFailure), request: kind)
		#expect(model.presentationError == "Import failed")
		#expect(pending.request == nil)
	}

	@Test("Cancelled imports finish quietly and stale callbacks cannot consume a newer request")
	func importCancellationAndStaleCallbacks() throws {
		let model = PreferencesPaneModel()
		var pending = PendingFileRequest<PreferencesImportRequest>()
		pending.present(.transcriptFolder)
		let first = try #require(pending.request)
		pending.dismiss(first.id)
		let completed = pending.complete(first.id)
		let kind = try #require(completed)
		model.completeImport(.failure(Self.cancellation), request: kind)
		#expect(model.presentationError == nil)
		#expect(pending.request == nil)

		pending.present(.transcriptFolder)
		let second = try #require(pending.request)
		#expect(second.id != first.id)
		pending.dismiss(first.id)
		#expect(pending.complete(first.id) == nil)
		#expect(pending.isPresented)
		#expect(pending.request?.id == second.id)
		#expect(model.presentationError == nil)
		#expect(pending.complete(second.id) != nil)
		#expect(!pending.isPresented)
		#expect(pending.request == nil)
	}

	@Test("A replaced picker ignores a late success instead of opening its URL")
	func supersededImportIgnoresSuccess() throws {
		let model = PreferencesPaneModel()
		var pending = PendingFileRequest<PreferencesImportRequest>()
		pending.present(.transcriptTheme)
		let first = try #require(pending.request)
		pending.present(.downloadFolder)
		let second = try #require(pending.request)
		#expect(pending.complete(first.id) == nil)
		#expect(model.presentationError == nil)
		#expect(pending.request?.id == second.id)
		#expect(pending.isPresented)
	}

	@Test("A selected theme URL is processed after the picker has dismissed")
	func selectedURLSurvivesDismissal() throws {
		let model = PreferencesPaneModel()
		var pending = PendingFileRequest<PreferencesImportRequest>()
		pending.present(.transcriptTheme)
		let request = try #require(pending.request)
		pending.dismiss(request.id)
		let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
		let completed = pending.complete(request.id)
		let kind = try #require(completed)
		model.completeImport(.success(missingURL), request: kind)
		// Reaching file validation proves the selected URL was not lost at dismissal.
		#expect(model.presentationError != nil)
		#expect(pending.request == nil)
	}

	/// A view going away drops whatever it was waiting on rather than leaving a
	/// request that the next appearance would answer.
	@Test("Resetting a pending request leaves nothing to complete")
	func resetDropsThePendingRequest() throws {
		var pending = PendingFileRequest<PreferencesImportRequest>()
		pending.present(.downloadFolder)
		let request = try #require(pending.request)
		pending.reset()
		#expect(pending.request == nil)
		#expect(!pending.isPresented)
		#expect(pending.complete(request.id) == nil)
	}

	/// A pane the sidebar cannot reach is a pane nobody can open.
	@Test("The catalog covers every declared pane")
	func paneCatalogCoversEveryDeclaredPane() {
		#expect(Set(PreferencesPaneCatalog.panes.map(\.identifier)) == Set(PreferencesPaneIdentifier.allCases))
	}
}
