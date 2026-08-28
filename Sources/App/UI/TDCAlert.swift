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

import AppKit
import CocoaExtensions

/// Which of an alert's up to three buttons the user chose. The names describe
/// button position, which is what the nib-era API promised its callers.
public enum TDCAlertResponse: UInt, Sendable {
	case `default` = 1000
	case alternate = 1001
	case other = 1002
}

/// Everything one alert needs. Building the request is separate from showing
/// it, which is what lets the suppression policy be exercised without a window
/// server.
@MainActor
public struct AlertRequest {
	public var title: String
	public var body: String
	public var defaultButton: String
	public var alternateButton: String?
	public var otherButton: String?
	/// The base key recording a "do not show again" choice. Without one the
	/// checkbox is not offered, because nothing would remember the answer.
	public var suppressionKey: String?
	public var suppressionText: String?
	public var accessoryView: NSView?
	public var style: NSAlert.Style

	public init(
		title: String,
		body: String,
		defaultButton: String,
		alternateButton: String? = nil,
		otherButton: String? = nil,
		suppressionKey: String? = nil,
		suppressionText: String? = nil,
		accessoryView: NSView? = nil,
		style: NSAlert.Style = .informational
	) {
		self.title = title
		self.body = body
		self.defaultButton = defaultButton
		self.alternateButton = alternateButton
		self.otherButton = otherButton
		self.suppressionKey = suppressionKey
		self.suppressionText = suppressionText
		self.accessoryView = accessoryView
		self.style = style
	}
}

/// What an alert came back with.
public struct AlertOutcome: Equatable, Sendable {
	public let response: TDCAlertResponse
	/// Whether the alert will not be shown again — either because the user
	/// ticked the checkbox now, or because a previous run recorded the choice
	/// and this run was skipped entirely.
	public let isSuppressed: Bool

	public init(response: TDCAlertResponse, isSuppressed: Bool) {
		self.response = response
		self.isSuppressed = isSuppressed
	}
}

public typealias TDCAlertCompletionBlock = @MainActor (AlertOutcome) -> Void

/// Where an alert appears.
@MainActor
public enum AlertPresentation {
	/// Blocks in its own modal loop.
	case applicationModal
	/// A sheet on a specific window.
	case sheet(NSWindow)
	/// A sheet on the main window, or on any other visible window while the
	/// main window is hidden. During launch and migration no window exists yet,
	/// and the alert runs application modal instead.
	case anyVisibleWindow
}

/// The AppKit half of showing an alert: build the panel, run it, report the
/// button and whether the suppression checkbox ended up ticked. Injected so
/// `TDCAlert`'s suppression policy is testable on its own.
@MainActor
public protocol AlertPresenter {
	func present(_ request: AlertRequest, in presentation: AlertPresentation) async -> AlertPresenterResult
	func presentModal(_ request: AlertRequest) -> AlertPresenterResult
}

public struct AlertPresenterResult: Equatable, Sendable {
	public let response: TDCAlertResponse
	public let suppressionChecked: Bool

	public init(response: TDCAlertResponse, suppressionChecked: Bool) {
		self.response = response
		self.suppressionChecked = suppressionChecked
	}
}

// MARK: - The one operation

public enum TDCAlert {
	private static let suppressionPrefix = Preferences.Families.alertSuppression.pattern

	/// Shows `request` and reports what the user chose. A request whose
	/// suppression key was already recorded is not shown at all; it reports
	/// `.default` and `isSuppressed`, which is the answer the user gave the
	/// last time they saw it.
	@MainActor
	@discardableResult
	public static func run(
		_ request: AlertRequest,
		on presentation: AlertPresentation,
		using presenter: any AlertPresenter = AppKitAlertPresenter()
	) async -> AlertOutcome {
		guard let prepared = prepare(request) else {
			return AlertOutcome(response: .default, isSuppressed: true)
		}

		let result = await presenter.present(prepared.request, in: presentation)
		return finish(result, suppressionKey: prepared.resolvedKey)
	}

	/// The blocking form, for the call sites that need the answer before they
	/// can continue.
	@MainActor
	@discardableResult
	public static func runModal(
		_ request: AlertRequest,
		using presenter: any AlertPresenter = AppKitAlertPresenter()
	) -> AlertOutcome {
		guard let prepared = prepare(request) else {
			return AlertOutcome(response: .default, isSuppressed: true)
		}

		let result = presenter.presentModal(prepared.request)
		return finish(result, suppressionKey: prepared.resolvedKey)
	}

	/// `nil` when the alert has already been suppressed and must not be shown.
	@MainActor
	private static func prepare(_ request: AlertRequest) -> (request: AlertRequest, resolvedKey: String?)? {
		var request = request

		guard let baseKey = request.suppressionKey else {
			return (request, nil)
		}

		let resolvedKey = suppressionKey(withBase: baseKey)

		guard isSuppressed(fullKey: resolvedKey) == false else {
			return nil
		}

		request.suppressionKey = resolvedKey

		if request.suppressionText?.isEmpty != false {
			request.suppressionText = PromptStrings.Alert.doNotShowAgain
		}

		return (request, resolvedKey)
	}

	@MainActor
	private static func finish(_ result: AlertPresenterResult, suppressionKey: String?) -> AlertOutcome {
		if result.suppressionChecked, let suppressionKey {
			suppressionFlag(suppressionKey).value = true
		}

		return AlertOutcome(response: result.response, isSuppressed: result.suppressionChecked)
	}
}

// MARK: - Suppression

public extension TDCAlert {
	/// Whether the user has previously chosen "do not show again" for an alert
	/// whose suppression key was `baseKey`.
	static func isSuppressed(baseKey: String) -> Bool {
		isSuppressed(fullKey: suppressionKey(withBase: baseKey))
	}

	internal static func isSuppressed(fullKey: String) -> Bool {
		suppressionFlag(fullKey).value
	}

	/** The suppression family is catalogued as a container key, but the flags
	 used to be written to `.standard`, so an imported "do not ask again" never
	 took effect and the two stores disagreed about what had been suppressed. */
	private static func suppressionFlag(_ fullKey: String) -> PreferenceKey<Bool> {
		PreferenceKey(fullKey, default: false, traits: [.unregistered, .uncatalogued])
	}

	static func suppressionKey(withBase base: String) -> String {
		if base.hasPrefix(suppressionPrefix) {
			return base
		}

		return suppressionPrefix + base
	}
}

// MARK: - AppKit presentation

/// Builds and runs a real `NSAlert`.
@MainActor
public struct AppKitAlertPresenter: AlertPresenter {
	public init() {}

	public func present(_ request: AlertRequest, in presentation: AlertPresentation) async -> AlertPresenterResult {
		let alert = Self.makeAlert(request)

		switch presentation {
		case .applicationModal:
			return Self.result(of: alert, returnCode: alert.runModal())

		case let .sheet(window):
			let returnCode = await alert.beginSheetModal(for: window)
			return Self.result(of: alert, returnCode: returnCode)

		case .anyVisibleWindow:
			guard let window = Self.hostWindow() else {
				return Self.result(of: alert, returnCode: alert.runModal())
			}
			let returnCode = await alert.beginSheetModal(for: window)
			return Self.result(of: alert, returnCode: returnCode)
		}
	}

	public func presentModal(_ request: AlertRequest) -> AlertPresenterResult {
		let alert = Self.makeAlert(request)
		return Self.result(of: alert, returnCode: alert.runModal())
	}

	private static func makeAlert(_ request: AlertRequest) -> NSAlert {
		let alert = NSAlert()
		alert.alertStyle = request.style
		alert.messageText = request.title
		alert.informativeText = request.body
		alert.addButton(withTitle: request.defaultButton)

		if let alternateButton = request.alternateButton {
			alert.addButton(withTitle: alternateButton)
		}

		if let otherButton = request.otherButton {
			alert.addButton(withTitle: otherButton)
		}

		/* Only a key can record the choice, so showing the checkbox without one gave
		 the user a "do not show again" control that did nothing. */
		if request.suppressionKey != nil {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = request.suppressionText ?? ""
		}

		if let accessoryView = request.accessoryView {
			alert.accessoryView = accessoryView
		}

		return alert
	}

	/** A sheet on the main window is preferred so that the alert is attached to
	 what it is about. When the main window is hidden, any other visible window
	 hosts the sheet instead. */
	private static func hostWindow() -> NSWindow? {
		if let mainWindow = AppController.shared.mainWindow, mainWindow.isVisible {
			return mainWindow
		}

		return NSApp.orderedWindows.first { window in
			window.isVisible && window.attachedSheet == nil && (window is NSPanel) == false
		}
	}

	private static func result(of alert: NSAlert, returnCode: NSApplication.ModalResponse) -> AlertPresenterResult {
		AlertPresenterResult(
			response: response(from: returnCode),
			suppressionChecked: alert.suppressionButton?.state == .on
		)
	}

	private static func response(from returnCode: NSApplication.ModalResponse) -> TDCAlertResponse {
		switch returnCode {
		case .alertSecondButtonReturn:
			.alternate
		case .alertThirdButtonReturn:
			.other
		default:
			.default
		}
	}
}

// MARK: - Convenience wrappers

public extension TDCAlert {
	/// A blocking two-button question. `true` is the default button.
	@MainActor
	static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		suppressionKey suppressKey: String? = nil,
		suppressionText suppressText: String? = nil
	) -> Bool {
		runModal(
			AlertRequest(
				title: titleText,
				body: bodyText,
				defaultButton: buttonDefault,
				alternateButton: buttonAlternate,
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
		suppressionKey suppressKey: String? = nil,
		suppressionText suppressText: String? = nil,
		completionBlock: TDCAlertCompletionBlock? = nil
	) {
		let request = AlertRequest(
			title: titleText,
			body: bodyText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: suppressKey,
			suppressionText: suppressText
		)

		Task { @MainActor in
			let outcome = await run(request, on: .anyVisibleWindow)
			completionBlock?(outcome)
		}
	}

	/// A non-blocking sheet on a specific window.
	@MainActor
	static func alertSheet(
		with window: NSWindow,
		body bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		suppressionKey suppressKey: String? = nil,
		suppressionText suppressText: String? = nil,
		completionBlock: TDCAlertCompletionBlock? = nil
	) {
		let request = AlertRequest(
			title: titleText,
			body: bodyText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: suppressKey,
			suppressionText: suppressText
		)

		Task { @MainActor in
			let outcome = await run(request, on: .sheet(window))
			completionBlock?(outcome)
		}
	}
}
