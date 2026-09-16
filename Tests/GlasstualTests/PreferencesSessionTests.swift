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

	@Test("External Settings navigation clears filters even for the already-selected destination", arguments: [
		SettingsSceneSelection.notifications, .style, .hiddenPreferences,
	])
	func externalNavigationClearsSearch(_ request: SettingsSceneSelection) {
		let rememberedSelection = Preferences.Internals.selectedPreferencePane.value
		let session = SettingsSession()
		defer {
			session.deactivate()
			Preferences.Internals.selectedPreferencePane.value = rememberedSelection
		}
		let expected: SettingsSelection = switch request {
		case .notifications: .notifications
		case .style: .style
		case .hiddenPreferences: .advanced
		case .default: .general
		}
		let unmatchedSearch = "__glasstual_no_settings_destination_7be2a913__"
		session.model.searchText = unmatchedSearch
		#expect(session.model.matchingDestinations.isEmpty)
		session.activate(selection: request)
		#expect(session.model.searchText.isEmpty)
		#expect(session.model.selection == expected)
		#expect(session.model.matchingDestinations.contains { $0.selection == expected })

		// The second request does not change selection, so observing selection
		// alone would leave the requested pane absent from the sidebar.
		session.model.searchText = unmatchedSearch
		#expect(session.model.matchingDestinations.isEmpty)
		session.activate(selection: request)
		#expect(session.model.searchText.isEmpty)
		#expect(session.model.selection == expected)
		#expect(session.model.matchingDestinations.contains { $0.selection == expected })
	}

	@Test("File importer dismissal retains the request until its completion is applied")
	func importCompletionSurvivesDismissal() throws {
		let model = SettingsModel()
		var pending = PendingFileRequest<SettingsImportRequest>()
		pending.present(.transcriptTheme)
		let request = try #require(pending.request)
		pending.dismiss(request.id)
		#expect(!pending.isPresented)
		#expect(pending.request?.kind == .transcriptTheme)
		let completed = pending.complete(request.id)
		let kind = try #require(completed)
		model.completeImport(.failure(Self.importFailure), request: kind)
		#expect(model.presentationFailure?.reason == "Import failed")
		#expect(pending.request == nil)
	}

	@Test("Cancelled imports finish quietly and stale callbacks cannot consume a newer request")
	func importCancellationAndStaleCallbacks() throws {
		let model = SettingsModel()
		var pending = PendingFileRequest<SettingsImportRequest>()
		pending.present(.transcriptFolder)
		let first = try #require(pending.request)
		pending.dismiss(first.id)
		let completed = pending.complete(first.id)
		let kind = try #require(completed)
		model.completeImport(.failure(Self.cancellation), request: kind)
		#expect(model.presentationFailure == nil)
		#expect(pending.request == nil)

		pending.present(.transcriptFolder)
		let second = try #require(pending.request)
		#expect(second.id != first.id)
		pending.dismiss(first.id)
		#expect(pending.complete(first.id) == nil)
		#expect(pending.isPresented)
		#expect(pending.request?.id == second.id)
		#expect(model.presentationFailure == nil)
		#expect(pending.complete(second.id) != nil)
		#expect(!pending.isPresented)
		#expect(pending.request == nil)
	}

	@Test("A replaced picker ignores a late success instead of opening its URL")
	func supersededImportIgnoresSuccess() throws {
		let model = SettingsModel()
		var pending = PendingFileRequest<SettingsImportRequest>()
		pending.present(.transcriptTheme)
		let first = try #require(pending.request)
		pending.present(.downloadFolder)
		let second = try #require(pending.request)
		#expect(pending.complete(first.id) == nil)
		#expect(model.presentationFailure == nil)
		#expect(pending.request?.id == second.id)
		#expect(pending.isPresented)
	}

	@Test("A selected theme URL is processed after the picker has dismissed")
	func selectedURLSurvivesDismissal() async throws {
		let model = SettingsModel()
		var pending = PendingFileRequest<SettingsImportRequest>()
		pending.present(.transcriptTheme)
		let request = try #require(pending.request)
		pending.dismiss(request.id)
		let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
		let completed = pending.complete(request.id)
		let kind = try #require(completed)
		model.completeImport(.success(missingURL), request: kind)
		/* The file is read off the main actor; reaching its validation proves
		 the selected URL was not lost at dismissal. */
		await model.themeImportTask?.value
		#expect(model.presentationFailure != nil)
		#expect(pending.request == nil)
	}

	/// A view going away drops whatever it was waiting on rather than leaving a
	/// request that the next appearance would answer.
	@Test("Resetting a pending request leaves nothing to complete")
	func resetDropsThePendingRequest() throws {
		var pending = PendingFileRequest<SettingsImportRequest>()
		pending.present(.downloadFolder)
		let request = try #require(pending.request)
		pending.reset()
		#expect(pending.request == nil)
		#expect(!pending.isPresented)
		#expect(pending.complete(request.id) == nil)
	}
}
