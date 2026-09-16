/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/// Showing an alert, and remembering the ones the reader asked not to see
/// again. Where an alert is drawn is `SystemAlertPresenter`'s question.
enum Alerts {
	private static let suppressionPrefix = Preferences.Families.alertSuppression.pattern

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

	/// The blocking form for launch and migration before a scene exists.
	@MainActor
	@discardableResult
	static func runModal(
		_ request: AlertRequest,
		using presenter: any AlertPresenter = SystemAlertPresenter()
	) -> AlertOutcome {
		guard case let .show(prepared, suppressionKey) = prepare(request) else {
			return suppressedOutcome(for: request)
		}

		let result = presenter.presentModal(prepared)
		return finish(result, suppressionKey: suppressionKey)
	}

	@MainActor
	private static func prepare(_ request: AlertRequest) -> PreparedAlert {
		var request = request

		guard let baseKey = request.suppressionKey else {
			return .show(request, suppressionKey: nil)
		}

		let resolvedKey = suppressionKey(withBase: baseKey)

		if let recorded = recordedResponse(fullKey: resolvedKey) {
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
			.flatMap { recordedResponse(fullKey: suppressionKey(withBase: $0)) } ?? .default
		return AlertOutcome(response: response, isSuppressed: true)
	}

	@MainActor
	private static func finish(_ result: AlertPresenterResult, suppressionKey: String?) -> AlertOutcome {
		if result.suppressionChecked, let suppressionKey {
			suppressionFlag(suppressionKey).value = true
			suppressionResponse(suppressionKey).value = result.response
		}

		return AlertOutcome(response: result.response, isSuppressed: result.suppressionChecked)
	}
}

// MARK: - Suppression

extension Alerts {
	/// Distinguishes the flag from the response recorded beside it. Both live
	/// in the alert suppression family, so both stay out of an export.
	private static var responseSuffix: String {
		" -> Response"
	}

	/// Whether the user has previously chosen "do not show again" for an alert
	/// whose suppression key was `baseKey`.
	static func isSuppressed(baseKey: String) -> Bool {
		isSuppressed(fullKey: suppressionKey(withBase: baseKey))
	}

	/// The button a suppressed alert answers with, or `nil` when the user has
	/// not chosen to stop seeing it.
	static func suppressedResponse(baseKey: String) -> AlertResponse? {
		recordedResponse(fullKey: suppressionKey(withBase: baseKey))
	}

	static func isSuppressed(fullKey: String) -> Bool {
		suppressionFlag(fullKey).value
	}

	/** The suppression family is catalogued as a container key, but the flags
	 used to be written to `.standard`, so an imported "do not ask again" never
	 took effect and the two stores disagreed about what had been suppressed. */
	private static func suppressionFlag(_ fullKey: String) -> PreferenceKey<Bool> {
		PreferenceKey(fullKey, default: false, traits: [.unregistered, .uncatalogued])
	}

	/** Which button was pressed when the checkbox was ticked.

	 Recording only *that* an alert was suppressed made every later run answer
	 with the default button, so a suppressed "No" opened the link or deleted
	 the channel anyway. Flags written before this key existed read back as
	 `.default`, which is the answer they used to give. */
	private static func suppressionResponse(_ fullKey: String) -> PreferenceKey<AlertResponse> {
		PreferenceKey(fullKey + responseSuffix, default: .default, traits: [.unregistered, .uncatalogued])
	}

	private static func recordedResponse(fullKey: String) -> AlertResponse? {
		guard isSuppressed(fullKey: fullKey) else {
			return nil
		}

		return suppressionResponse(fullKey).value
	}

	static func suppressionKey(withBase base: String) -> String {
		if base.hasPrefix(suppressionPrefix) {
			return base
		}

		return suppressionPrefix + base
	}
}

// MARK: - Convenience wrappers

extension Alerts {
	/// A blocking two-button question. `true` is the default button.
	@MainActor
	static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		destructiveButton buttonDestructive: AlertDestructiveButton? = nil,
		cancelButton buttonCancel: AlertResponse? = nil,
		suppressionKey suppressKey: String? = nil,
		suppressionText suppressText: String? = nil
	) -> Bool {
		runModal(
			AlertRequest(
				title: titleText,
				body: bodyText,
				defaultButton: buttonDefault,
				alternateButton: buttonAlternate,
				destructiveButton: buttonDestructive,
				cancelButton: buttonCancel,
				suppressionKey: suppressKey,
				suppressionText: suppressText,
				style: .warning
			)
		).response == .default
	}

	/// A non-blocking alert shown wherever the application can host one.
	@MainActor
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String? = nil,
		otherButton buttonOther: String? = nil,
		destructiveButton buttonDestructive: AlertDestructiveButton? = nil,
		cancelButton buttonCancel: AlertResponse? = nil,
		suppressionKey suppressKey: String? = nil,
		suppressionText suppressText: String? = nil,
		completionBlock: AlertCompletion? = nil
	) {
		let request = AlertRequest(
			title: titleText,
			body: bodyText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			destructiveButton: buttonDestructive,
			cancelButton: buttonCancel,
			suppressionKey: suppressKey,
			suppressionText: suppressText
		)

		Task { @MainActor in
			let outcome = await run(request, on: .anyVisibleWindow)
			completionBlock?(outcome)
		}
	}

	/// A non-blocking sheet on the main window.
	@MainActor
	static func alertSheet(
		body bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		destructiveButton buttonDestructive: AlertDestructiveButton? = nil,
		cancelButton buttonCancel: AlertResponse? = nil,
		suppressionKey suppressKey: String? = nil,
		suppressionText suppressText: String? = nil,
		completionBlock: AlertCompletion? = nil
	) {
		let request = AlertRequest(
			title: titleText,
			body: bodyText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			destructiveButton: buttonDestructive,
			cancelButton: buttonCancel,
			suppressionKey: suppressKey,
			suppressionText: suppressText
		)

		alertSheet(request: request, completionBlock: completionBlock)
	}

	/// The same sheet, taking the request whole. What a caller that already has
	/// an `AlertRequest` — the protocol layer, through `ClientOutput` — needs.
	static func alertSheet(
		request: AlertRequest,
		completionBlock: AlertCompletion? = nil
	) {
		Task { @MainActor in
			let outcome = await run(request, on: .mainWindow)
			completionBlock?(outcome)
		}
	}
}
