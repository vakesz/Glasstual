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

/// So the button a suppressed alert answers with can be stored beside the flag.
extension AlertResponse: PreferenceEnum {}

/// Everything one alert needs. Building the request is separate from showing
/// it, which is what lets the suppression policy be exercised without a window
/// server.
public nonisolated enum AlertStyle: Sendable { // nonisolated: value
	case informational
	case warning
	case critical
}

/// Which of an alert's buttons destroys something. The panel gives that button
/// the destructive role, which is what tints it and tells VoiceOver the action
/// cannot be taken back.
public nonisolated enum AlertDestructiveButton: Sendable { // nonisolated: value
	case `default`
	case alternate
}

public nonisolated struct AlertRequest: Sendable { // nonisolated: value
	public var title: String
	public var body: String
	public var defaultButton: String
	public var alternateButton: String?
	public var otherButton: String?
	public var destructiveButton: AlertDestructiveButton?
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
		destructiveButton: AlertDestructiveButton? = nil,
		suppressionKey: String? = nil,
		suppressionText: String? = nil,
		style: AlertStyle = .informational
	) {
		self.title = title
		self.body = body
		self.defaultButton = defaultButton
		self.alternateButton = alternateButton
		self.otherButton = otherButton
		self.destructiveButton = destructiveButton
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

/// The presentation half of showing an alert: build the panel, run it, report the
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
	public static func run(
		_ request: AlertRequest,
		on presentation: AlertPresentation,
		using presenter: any AlertPresenter = SwiftUIAlertPresenter()
	) async -> AlertOutcome {
		guard case let .show(prepared, suppressionKey) = prepare(request) else {
			return suppressedOutcome(for: request)
		}

		let result = await presenter.present(prepared, in: presentation)
		return finish(result, suppressionKey: suppressionKey)
	}

	/// The blocking form, for the call sites that need the answer before they
	/// can continue.
	@MainActor
	@discardableResult
	public static func runModal(
		_ request: AlertRequest,
		using presenter: any AlertPresenter = SwiftUIAlertPresenter()
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

public extension Alerts {
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

	internal static func isSuppressed(fullKey: String) -> Bool {
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

// MARK: - SwiftUI presentation

/// The checkbox state the panel writes and the session reads back.
@MainActor
@Observable
private final class AlertPresentationModel {
	var suppressionChecked = false
}

/** The panel every alert is drawn with, to the proportions the system uses.

 SwiftUI owns presentation, so the alert look is built here rather than handed
 to a panel class: the application icon over a centred title and message, the
 buttons in one row along the bottom ordered right to left, a third button on
 the far left, and the suppression checkbox above them. Escape and ⌘. answer
 the cancel button, Return the default one, and a destructive button carries
 the role that tints it and tells VoiceOver the action cannot be taken back. */
@MainActor
private struct AlertPanelView: View {
	private enum Metrics {
		/// What a system alert gives its text, and what the panel is sized from.
		static let contentWidth: CGFloat = 260
		static let iconSize: CGFloat = 64
		static let badgeSize: CGFloat = 26
	}

	@Bindable var model: AlertPresentationModel
	let request: AlertRequest
	let respond: (AlertResponse) -> Void

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@Environment(\.colorSchemeContrast) private var colorSchemeContrast
	@State private var hasAppeared = false

	var body: some View {
		VStack(spacing: 16) {
			icon
			message

			if request.suppressionKey != nil {
				suppression
			}

			buttons
		}
		.frame(width: Metrics.contentWidth)
		.padding(.horizontal, 20)
		.padding(.top, 18)
		.padding(.bottom, 16)
		.opacity(hasAppeared ? 1 : 0)
		.animation(appearanceAnimation, value: hasAppeared)
		.onAppear { hasAppeared = true }
	}

	/// The application icon, badged with the system caution mark for the two
	/// styles that warn, which is how the system draws its own alerts.
	@ViewBuilder private var icon: some View {
		if let applicationIcon = NSApp.applicationIconImage {
			Image(nsImage: applicationIcon)
				.resizable()
				.frame(width: Metrics.iconSize, height: Metrics.iconSize)
				.overlay(alignment: .bottomTrailing) { badge }
				.accessibilityHidden(true)
		}
	}

	@ViewBuilder private var badge: some View {
		if let cautionIcon {
			Image(nsImage: cautionIcon)
				.resizable()
				.frame(width: Metrics.badgeSize, height: Metrics.badgeSize)
				.offset(x: 6, y: 6)
		}
	}

	private var cautionIcon: NSImage? {
		switch request.style {
		case .informational: nil
		case .warning, .critical: NSImage(named: NSImage.cautionName)
		}
	}

	private var message: some View {
		VStack(spacing: 6) {
			Text(verbatim: request.title)
				.font(.headline)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)

			if request.body.isEmpty == false {
				Text(verbatim: request.body)
					.font(.subheadline)
					.foregroundStyle(bodyStyle)
					.multilineTextAlignment(.center)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity)
	}

	private var suppression: some View {
		Toggle(isOn: $model.suppressionChecked) {
			Text(verbatim: request.suppressionText ?? PromptStrings.Alert.doNotAskAgain)
				.font(.subheadline)
		}
		.toggleStyle(.checkbox)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var buttons: some View {
		HStack(spacing: 12) {
			if let otherButton = request.otherButton {
				Button(otherButton) { respond(.other) }
			}

			Spacer(minLength: 0)

			if let alternateButton = request.alternateButton {
				Button(alternateButton, role: role(for: .alternate)) { respond(.alternate) }
					.keyboardShortcut(.cancelAction)
			}

			Button(request.defaultButton, role: role(for: .default)) { respond(.default) }
				.keyboardShortcut(.defaultAction)
				.buttonStyle(.borderedProminent)
				/* A prominent button keeps the accent colour whatever its role;
				 the system alert draws a destructive default in red. */
				.tint(role(for: .default) == .destructive ? Color.red : nil)
		}
		.frame(maxWidth: .infinity)
	}

	private func role(for button: AlertDestructiveButton) -> ButtonRole? {
		request.destructiveButton == button ? .destructive : nil
	}

	/// Increased contrast asks for the secondary text to stop being secondary.
	private var bodyStyle: HierarchicalShapeStyle {
		colorSchemeContrast == .increased ? .primary : .secondary
	}

	private var appearanceAnimation: Animation? {
		reduceMotion ? nil : .easeOut(duration: 0.12)
	}
}

/** Hosts the SwiftUI panel in the one AppKit boundary an alert still needs.

 A window, because an alert has to be answerable during launch and migration,
 before the application has a scene; and `beginSheet`, because a sheet has to
 be attachable to a window SwiftUI does not own. The main window has a
 state-driven sheet stack of its own, and that is what the alert uses there. */
@MainActor
private final class AlertPresentationSession {
	private enum Host {
		case unattached
		case modal(NSWindow)
		case sheet(parent: NSWindow, panel: NSWindow)
		case mainWindowSheet(MainWindow)
	}

	private let request: AlertRequest
	private let model = AlertPresentationModel()
	private var host: Host = .unattached
	private var response: AlertResponse?
	private var continuation: CheckedContinuation<AlertPresenterResult, Never>?

	init(request: AlertRequest) {
		self.request = request
	}

	func presentModal() -> AlertPresenterResult {
		let window = makeWindow()
		host = .modal(window)
		window.center()

		let code = NSApp.runModal(for: window)

		window.orderOut(nil)
		return finish(code)
	}

	func presentSheet(on parent: NSWindow) async -> AlertPresenterResult {
		let panel = makeWindow()
		host = .sheet(parent: parent, panel: panel)

		let code = await withCheckedContinuation { continuation in
			parent.beginSheet(panel) { continuation.resume(returning: $0) }
		}

		return finish(code)
	}

	func presentSheet(in mainWindow: MainWindow) async -> AlertPresenterResult {
		host = .mainWindowSheet(mainWindow)

		return await withCheckedContinuation { continuation in
			self.continuation = continuation
			mainWindow.presentationModel.presentSheet(MainWindowSheetPresentation(
				owner: self,
				content: makeView(),
				onDismiss: { [weak self] in self?.finishMainWindowSheet() }
			))
		}
	}

	private func makeWindow() -> NSWindow {
		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: NSSize(width: 300, height: 200)),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		let hostingController = NSHostingController(rootView: makeView())

		window.contentViewController = hostingController
		hostingController.view.layoutSubtreeIfNeeded()
		window.setContentSize(hostingController.view.fittingSize)
		// The panel carries its own centred title, so the frame carries none.
		window.titlebarAppearsTransparent = true
		window.titleVisibility = .hidden
		window.title = request.title
		window.isMovableByWindowBackground = false
		window.isReleasedWhenClosed = false
		window.isRestorable = false
		window.tabbingMode = .disallowed
		window.preventsApplicationTerminationWhenModal = false
		window.autorecalculatesKeyViewLoop = true

		return window
	}

	private func makeView() -> AlertPanelView {
		AlertPanelView(
			model: model,
			request: request,
			respond: { [weak self] response in self?.end(with: response) }
		)
	}

	private func end(with response: AlertResponse) {
		self.response = response
		let code = NSApplication.ModalResponse(rawValue: Int(response.rawValue))

		switch host {
		case .unattached:
			break
		case .modal:
			NSApp.stopModal(withCode: code)
		case let .sheet(parent, panel):
			parent.endSheet(panel, returnCode: code)
		case let .mainWindowSheet(mainWindow):
			mainWindow.presentationModel.dismissSheet(ownedBy: self)
		}
	}

	private func finish(_ code: NSApplication.ModalResponse) -> AlertPresenterResult {
		let result = AlertPresenterResult(
			response: resolvedResponse(code),
			suppressionChecked: model.suppressionChecked
		)

		// Drops the hosting controller, and with it the panel's view tree.
		switch host {
		case let .modal(panel), let .sheet(_, panel):
			panel.contentViewController = nil
		case .unattached, .mainWindowSheet:
			break
		}

		host = .unattached
		return result
	}

	private func finishMainWindowSheet() {
		let result = AlertPresenterResult(
			response: response ?? dismissedResponse,
			suppressionChecked: model.suppressionChecked
		)
		host = .unattached
		continuation?.resume(returning: result)
		continuation = nil
	}

	/** A modal session or a sheet someone else ended — `abort` or `stop` while
	 the application is quitting, say — never answered the question, so it
	 reads as the cancel button instead of silently agreeing to the default. */
	private func resolvedResponse(_ code: NSApplication.ModalResponse) -> AlertResponse {
		guard code.rawValue >= 0,
		      let response = AlertResponse(rawValue: UInt(code.rawValue))
		else {
			return dismissedResponse
		}

		return response
	}

	private var dismissedResponse: AlertResponse {
		request.alternateButton == nil ? .default : .alternate
	}
}

/// Runs alerts as the SwiftUI panel above: a sheet where a window can host
/// one, and a blocking window during launch and migration, before any scene
/// exists.
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
			if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
				return await session.presentSheet(on: window)
			}
			return session.presentModal()
		}
	}

	public func presentModal(_ request: AlertRequest) -> AlertPresenterResult {
		/* The session has to outlive the modal loop it runs: the panel holds it
		 weakly, so a temporary would be gone before the first button press. */
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
		destructiveButton buttonDestructive: AlertDestructiveButton? = nil,
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
