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
import Observation
import SwiftUI

/// Which of an alert's up to three buttons the user chose. The names describe
/// button position, which is what the nib-era API promised its callers.
public nonisolated enum AlertResponse: UInt, Sendable { // nonisolated: value
	case `default` = 1000
	case alternate = 1001
	case other = 1002
}

/// Everything one alert needs. Building the request is separate from showing
/// it, which is what lets the suppression policy be exercised without a window
/// server.
public nonisolated enum AlertStyle: Sendable { // nonisolated: value
	case informational
	case warning
	case critical
}

public nonisolated struct AlertRequest: Sendable { // nonisolated: value
	public var title: String
	public var body: String
	public var defaultButton: String
	public var alternateButton: String?
	public var otherButton: String?
	/// The base key recording a "do not show again" choice. Without one the
	/// checkbox is not offered, because nothing would remember the answer.
	public var suppressionKey: String?
	public var suppressionText: String?
	public var style: AlertStyle

	public init(
		title: String,
		body: String,
		defaultButton: String,
		alternateButton: String? = nil,
		otherButton: String? = nil,
		suppressionKey: String? = nil,
		suppressionText: String? = nil,
		style: AlertStyle = .informational
	) {
		self.title = title
		self.body = body
		self.defaultButton = defaultButton
		self.alternateButton = alternateButton
		self.otherButton = otherButton
		self.suppressionKey = suppressionKey
		self.suppressionText = suppressionText
		self.style = style
	}
}

/// What an alert came back with.
public nonisolated struct AlertOutcome: Equatable, Sendable { // nonisolated: value
	public let response: AlertResponse
	/// Whether the alert will not be shown again — either because the user
	/// ticked the checkbox now, or because a previous run recorded the choice
	/// and this run was skipped entirely.
	public let isSuppressed: Bool

	public init(response: AlertResponse, isSuppressed: Bool) {
		self.response = response
		self.isSuppressed = isSuppressed
	}
}

public typealias AlertCompletion = @MainActor (AlertOutcome) -> Void

/// Where an alert appears.
@MainActor
public enum AlertPresentation {
	/// Blocks in its own modal loop.
	case applicationModal
	/// A state-driven sheet on the application's main window.
	case mainWindow
	/// A sheet on the main window, or on any other visible window while the
	/// main window is hidden. During launch and migration no window exists yet,
	/// and the alert runs application modal instead.
	case anyVisibleWindow
}

/// The AppKit half of showing an alert: build the panel, run it, report the
/// button and whether the suppression checkbox ended up ticked. Injected so
/// `Alerts`'s suppression policy is testable on its own.
@MainActor
public protocol AlertPresenter {
	func present(_ request: AlertRequest, in presentation: AlertPresentation) async -> AlertPresenterResult
	func presentModal(_ request: AlertRequest) -> AlertPresenterResult
}

public nonisolated struct AlertPresenterResult: Equatable, Sendable { // nonisolated: value
	public let response: AlertResponse
	public let suppressionChecked: Bool

	public init(response: AlertResponse, suppressionChecked: Bool) {
		self.response = response
		self.suppressionChecked = suppressionChecked
	}
}

// MARK: - The one operation

public enum Alerts {
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
		using presenter: any AlertPresenter = SwiftUIAlertPresenter()
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
		using presenter: any AlertPresenter = SwiftUIAlertPresenter()
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

public extension Alerts {
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

// MARK: - SwiftUI presentation

@MainActor
@Observable
private final class AlertPresentationModel {
	var suppressionChecked = false
}

@MainActor
private struct AlertView: View {
	@Bindable var model: AlertPresentationModel
	let request: AlertRequest
	let respond: (AlertResponse) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			HStack(alignment: .top, spacing: 14) {
				Image(systemName: symbolName)
					.font(.system(size: 30))
					.foregroundStyle(symbolColor)
					.accessibilityHidden(true)

				VStack(alignment: .leading, spacing: 6) {
					Text(verbatim: request.title)
						.font(.headline)
					Text(verbatim: request.body)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}

			if request.suppressionKey != nil {
				Toggle(request.suppressionText ?? "", isOn: $model.suppressionChecked)
			}

			HStack {
				Spacer()

				if let otherButton = request.otherButton {
					Button(otherButton) {
						respond(.other)
					}
				}

				if let alternateButton = request.alternateButton {
					Button(alternateButton) {
						respond(.alternate)
					}
					.keyboardShortcut(.cancelAction)
				}

				Button(request.defaultButton) {
					respond(.default)
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(20)
		.frame(width: 430)
	}

	private var symbolName: String {
		switch request.style {
		case .informational: "info.circle"
		case .warning: "exclamationmark.triangle.fill"
		case .critical: "xmark.octagon.fill"
		}
	}

	private var symbolColor: Color {
		switch request.style {
		case .informational: .accentColor
		case .warning: .orange
		case .critical: .red
		}
	}
}

/// Hosts SwiftUI alert content in the AppKit window boundary required for
/// attaching a sheet to an arbitrary existing window or running a modal alert
/// before the application has a SwiftUI scene.
@MainActor
private final class AlertPresentationSession {
	private let request: AlertRequest
	private let model = AlertPresentationModel()
	private weak var mainWindow: MainWindow?
	private var alertWindow: NSWindow?
	private var response: AlertResponse = .default
	private var continuation: CheckedContinuation<AlertPresenterResult, Never>?

	init(request: AlertRequest) {
		self.request = request
	}

	func presentModal() -> AlertPresenterResult {
		let window = makeWindow()
		window.center()
		let returnCode = NSApp.runModal(for: window)
		window.orderOut(nil)
		return finish(returnCode)
	}

	func presentSheet(in mainWindow: MainWindow) async -> AlertPresenterResult {
		self.mainWindow = mainWindow

		return await withCheckedContinuation { continuation in
			self.continuation = continuation
			mainWindow.presentationModel.presentSheet(MainWindowSheetPresentation(
				owner: self,
				content: makeView(),
				onDismiss: { [weak self] in self?.finishSwiftUISheet() }
			))
		}
	}

	private func makeWindow() -> NSWindow {
		precondition(alertWindow == nil)

		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: NSSize(width: 430, height: 180)),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		let rootView = makeView()
		let hostingController = NSHostingController(rootView: rootView)

		window.contentViewController = hostingController
		hostingController.view.layoutSubtreeIfNeeded()
		window.setContentSize(hostingController.view.fittingSize)
		window.isReleasedWhenClosed = false
		window.isRestorable = false
		window.tabbingMode = .disallowed
		window.preventsApplicationTerminationWhenModal = false
		window.title = request.title
		window.autorecalculatesKeyViewLoop = true
		alertWindow = window

		return window
	}

	private func makeView() -> AlertView {
		AlertView(
			model: model,
			request: request,
			respond: { [weak self] response in self?.end(with: response) }
		)
	}

	private func end(with response: AlertResponse) {
		self.response = response

		if let mainWindow {
			mainWindow.presentationModel.dismissSheet(ownedBy: self)
			return
		}

		guard alertWindow != nil else { return }
		let returnCode = NSApplication.ModalResponse(rawValue: Int(response.rawValue))

		NSApp.stopModal(withCode: returnCode)
	}

	private func finishSwiftUISheet() {
		let result = AlertPresenterResult(
			response: response,
			suppressionChecked: model.suppressionChecked
		)
		mainWindow = nil
		continuation?.resume(returning: result)
		continuation = nil
	}

	private func finish(_: NSApplication.ModalResponse) -> AlertPresenterResult {
		let result = AlertPresenterResult(
			response: response,
			suppressionChecked: model.suppressionChecked
		)
		alertWindow?.contentViewController = nil
		alertWindow = nil
		return result
	}
}

@MainActor
public struct SwiftUIAlertPresenter: AlertPresenter {
	public init() {}

	public func present(_ request: AlertRequest, in presentation: AlertPresentation) async -> AlertPresenterResult {
		let session = AlertPresentationSession(request: request)

		switch presentation {
		case .applicationModal:
			return session.presentModal()
		case .mainWindow:
			guard let mainWindow = AppController.shared.mainWindow else {
				return session.presentModal()
			}
			return await session.presentSheet(in: mainWindow)
		case .anyVisibleWindow:
			if let mainWindow = AppController.shared.mainWindow, mainWindow.isVisible {
				return await session.presentSheet(in: mainWindow)
			}
			return session.presentModal()
		}
	}

	public func presentModal(_ request: AlertRequest) -> AlertPresenterResult {
		let session = AlertPresentationSession(request: request)
		return session.presentModal()
	}
}

// MARK: - Convenience wrappers

public extension Alerts {
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
		completionBlock: AlertCompletion? = nil
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
		with _: MainWindow,
		body bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
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
			suppressionKey: suppressKey,
			suppressionText: suppressText
		)

		alertSheet(request: request, completionBlock: completionBlock)
	}

	/// The same sheet, taking the request whole. What a caller that already has
	/// an `AlertRequest` — the protocol layer, through `ClientOutput` — needs.
	static func alertSheet(
		with _: MainWindow,
		request: AlertRequest,
		completionBlock: AlertCompletion? = nil
	) {
		alertSheet(request: request, completionBlock: completionBlock)
	}

	private static func alertSheet(
		request: AlertRequest,
		completionBlock: AlertCompletion?
	) {
		Task { @MainActor in
			let outcome = await run(request, on: .mainWindow)
			completionBlock?(outcome)
		}
	}
}
