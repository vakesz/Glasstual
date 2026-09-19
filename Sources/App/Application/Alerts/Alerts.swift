// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Showing an alert, and skipping the ones the reader asked not to see again.
/// Where an alert is drawn is `SystemAlertPresenter`'s question; what has been
/// suppressed is `AlertSuppression`'s.
enum Alerts {
	/// Whether the alert has to be shown, or the answer a previous run recorded.
	private enum PreparedAlert {
		case show(AlertRequest, suppressionKey: String?)
		case suppressed(AlertResponse)
	}

	/// Shows `request` and reports what the user chose. A request whose
	/// suppression key was already recorded is not shown at all; it repeats the
	/// button the user pressed the last time they saw it, so ticking the
	/// checkbox on a "No" keeps answering "No".
	@MainActor
	@discardableResult
	static func run(
		_ request: AlertRequest,
		on presentation: AlertPresentation,
		using presenter: any AlertPresenter = SystemAlertPresenter()
	) async -> AlertOutcome {
		guard !Task.isCancelled else {
			return AlertOutcome(response: request.escapeButton, isSuppressed: false)
		}
		guard case let .show(prepared, suppressionKey) = prepare(request) else {
			return suppressedOutcome(for: request)
		}

		let result = await presenter.present(prepared, in: presentation)
		return finish(result, suppressionKey: suppressionKey)
	}

	@MainActor
	private static func prepare(_ request: AlertRequest) -> PreparedAlert {
		var request = request

		guard let baseKey = request.suppressionKey else {
			return .show(request, suppressionKey: nil)
		}

		let resolvedKey = AlertSuppression.suppressionKey(withBase: baseKey)

		if let recorded = AlertSuppression.recordedResponse(fullKey: resolvedKey) {
			return .suppressed(recorded)
		}

		request.suppressionKey = resolvedKey

		if request.suppressionText?.isEmpty != false {
			request.suppressionText = PromptStrings.Alert.doNotAskAgain
		}

		return .show(request, suppressionKey: resolvedKey)
	}

	@MainActor
	private static func suppressedOutcome(for request: AlertRequest) -> AlertOutcome {
		let response = request.suppressionKey
			.flatMap { AlertSuppression.suppressedResponse(baseKey: $0) } ?? .default
		return AlertOutcome(response: response, isSuppressed: true)
	}

	@MainActor
	private static func finish(_ result: AlertPresenterResult, suppressionKey: String?) -> AlertOutcome {
		if result.suppressionChecked, let suppressionKey {
			AlertSuppression.record(result.response, fullKey: suppressionKey)
		}

		return AlertOutcome(response: result.response, isSuppressed: result.suppressionChecked)
	}
}

// MARK: - Convenience wrappers

extension Alerts {
	/// A non-blocking alert shown wherever the application can host one. The
	/// arguments are `AlertRequest`'s own, so the call reads as the request it
	/// builds.
	@MainActor
	static func alert(
		title: String,
		body: String,
		defaultButton: String,
		alternateButton: String? = nil,
		otherButton: String? = nil,
		destructiveButton: AlertDestructiveButton? = nil,
		cancelButton: AlertResponse? = nil,
		suppressionKey: String? = nil,
		suppressionText: String? = nil,
		completion: AlertCompletion? = nil
	) {
		let request = AlertRequest(
			title: title,
			body: body,
			defaultButton: defaultButton,
			alternateButton: alternateButton,
			otherButton: otherButton,
			destructiveButton: destructiveButton,
			cancelButton: cancelButton,
			suppressionKey: suppressionKey,
			suppressionText: suppressionText
		)

		Task { @MainActor in
			let outcome = await run(request, on: .anyVisibleWindow)
			completion?(outcome)
		}
	}

	/// A non-blocking sheet on the main window.
	@MainActor
	static func alertSheet(
		title: String,
		body: String,
		defaultButton: String,
		alternateButton: String? = nil,
		otherButton: String? = nil,
		destructiveButton: AlertDestructiveButton? = nil,
		cancelButton: AlertResponse? = nil,
		suppressionKey: String? = nil,
		suppressionText: String? = nil,
		completion: AlertCompletion? = nil
	) {
		let request = AlertRequest(
			title: title,
			body: body,
			defaultButton: defaultButton,
			alternateButton: alternateButton,
			otherButton: otherButton,
			destructiveButton: destructiveButton,
			cancelButton: cancelButton,
			suppressionKey: suppressionKey,
			suppressionText: suppressionText
		)

		alertSheet(request: request, completion: completion)
	}

	/// The same sheet, taking the request whole. What a caller that already has
	/// an `AlertRequest` — the protocol layer, through `ServerSessionPresenting` — needs.
	static func alertSheet(
		request: AlertRequest,
		completion: AlertCompletion? = nil
	) {
		Task { @MainActor in
			let outcome = await run(request, on: .mainWindow)
			completion?(outcome)
		}
	}
}

// MARK: - Credential failures

/// Shared, stateless presentation for credential failures in editors and at
/// shutdown. The persistence service receives its presenter from the application.
enum KeychainAlerts {
	static func terminationFailureAlert(_ error: any Error) -> AlertRequest {
		AlertRequest(
			title: String(localized: .Prompts.keychainSaveFailedTitle),
			body: error.localizedDescription + "\n\n" + String(localized: .Prompts.keychainQuitSaveFailedBody),
			defaultButton: String(localized: .Prompts.keychainRetrySave),
			alternateButton: String(localized: .Prompts.keychainQuitWithoutSaving),
			cancelButton: .default
		)
	}

	static func confirmTerminationRetry(_ error: any Error) async -> Bool {
		await Alerts.run(terminationFailureAlert(error), on: .mainWindow).response == .default
	}

	static func failureAlert(_ error: any Error, canRetry: Bool) -> AlertRequest {
		AlertRequest(
			title: String(localized: .Prompts.keychainSaveFailedTitle),
			body: error.localizedDescription,
			defaultButton: canRetry ? String(localized: .Prompts.keychainRetrySave) : PromptStrings.Action.confirmation,
			alternateButton: canRetry ? PromptStrings.Action.cancel : nil,
			otherButton: nil,
			cancelButton: canRetry ? .alternate : .default
		)
	}

	static func showFailure(_ error: any Error, retry: (() -> Void)? = nil) {
		Alerts.alertSheet(request: failureAlert(error, canRetry: retry != nil)) { outcome in
			if outcome.response == .default {
				retry?()
			}
		}
	}
}

// MARK: - Transcript logging failures

/// Telling the user that transcript logging stopped because the disk filled up.
/// The file sink reports the condition; deciding to interrupt anyone about it,
/// and drawing the alert, happens here.
enum FileLogAlerts {
	private static var noSpaceAlert = FileLogAlertThrottle()

	static func reportNoSpace(at now: Date = Date()) {
		guard !FileLogger.isTerminating, noSpaceAlert.begin(at: now) else { return }
		Alerts.alert(
			title: PromptStrings.Logging.disabledForLowStorageTitle,
			body: PromptStrings.Logging.resumeAfterLowStorageBody,
			defaultButton: PromptStrings.Action.confirmation
		) { _ in
			noSpaceAlert.dismiss()
		}
	}
}

/** How often the low-storage alert may be raised.

 One alert at a time, and one every five minutes at most: a full disk fails
 every write, and the user is told once rather than once per line. */
nonisolated struct FileLogAlertThrottle {
	private var visible = false
	private var lastAlert: Date?

	mutating func begin(at now: Date) -> Bool {
		guard !visible else { return false }
		if let lastAlert, now.timeIntervalSince(lastAlert) < 300 {
			return false
		}
		lastAlert = now
		visible = true
		return true
	}

	mutating func dismiss() {
		visible = false
	}
}
