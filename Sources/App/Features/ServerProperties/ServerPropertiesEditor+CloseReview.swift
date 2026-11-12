// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// The answer to the question a Server Properties window asks before its
/// unsaved edits would be lost.
enum ServerPropertiesCloseAnswer: Equatable {
	case save
	case dontSave
	case cancel

	init(_ response: AlertResponse) {
		self = switch response {
		case .default: .save
		case .alternate: .cancel
		case .other: .dontSave
		}
	}
}

extension ServerPropertiesEditor {
	/// What closing the window does now: nothing unsaved closes it, edits ask
	/// first, and a save still under way keeps it open until it finishes.
	var closePolicy: WindowClosePolicy {
		if model.isSaving {
			return .refuses
		}
		return model.hasUnsavedChanges ? .asks : .closes
	}

	/// Where the window's own questions appear: on the window, once it is on
	/// screen.
	var alertPresentation: AlertPresentation {
		closeReview?.window.map(AlertPresentation.window) ?? .mainWindow
	}

	/** The question asked before unsaved edits would be lost, as a document
	 window asks it: Save is the default, Cancel answers Escape, and Don't Save
	 is set apart on the left. */
	static func closeReviewRequest(windowTitle: String) -> AlertRequest {
		var request = AlertRequest(
			title: String(localized: .ServerProperties.closeReviewTitle(windowTitle)),
			body: String(localized: .ServerProperties.closeReviewBody),
			defaultButton: PromptStrings.Action.save,
			alternateButton: PromptStrings.Action.cancel,
			otherButton: String(localized: .ServerProperties.dontSaveButton),
			style: .warning,
			allowsInline: false
		)
		request.accessibilityIdentifier = AccessibilityIdentifier.serverPropertiesCloseReview
		return request
	}

	/// Someone tried to close the window with edits in it: ask, and close it
	/// once the edits are saved or thrown away.
	func closeRequestedWithUnsavedChanges() {
		Task {
			guard await reviewUnsavedChanges() else { return }
			closeWindow()
		}
	}

	/** Asks what to do with the edits, on this window, and carries out the
	 answer. `true` once nothing unsaved is left in the way; `false` when the
	 person cancelled or the save failed, and the edits stay. A second request
	 while the question is up waits for no answer of its own. */
	func reviewUnsavedChanges() async -> Bool {
		guard model.hasUnsavedChanges else { return true }
		guard isReviewingUnsavedChanges == false else { return false }
		isReviewingUnsavedChanges = true
		defer { isReviewingUnsavedChanges = false }
		let outcome = await Alerts.run(Self.closeReviewRequest(windowTitle: windowTitle), on: alertPresentation)
		return await answerCloseReview(ServerPropertiesCloseAnswer(outcome.response))
	}

	/** Carries out an answer to the close review: Save keeps the window open
	 when the save fails, Don't Save throws the edits away, and Cancel leaves
	 everything as it is. `true` when the edits are out of the way. */
	func answerCloseReview(_ answer: ServerPropertiesCloseAnswer) async -> Bool {
		switch answer {
		case .save:
			return await save()
		case .dontSave:
			cancel()
			return true
		case .cancel:
			return false
		}
	}

	/// Closes the window once its edits are dealt with. A new connection's
	/// window is already on its way out after Save or Don't Save.
	private func closeWindow() {
		guard closeRequested == false else { return }
		closeReview?.close()
	}
}
