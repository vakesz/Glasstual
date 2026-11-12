// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

/** Shows alerts with `NSAlert`.

 The system panel is what an alert is: it draws the application icon, badges it
 with the caution mark for the two styles that warn, orders the buttons right to
 left with a third on the far left, tints a destructive button, offers the
 suppression checkbox and follows whatever macOS changes about alert chrome.
 This used to be a SwiftUI view that reproduced all of it by hand.

 AppKit is still the boundary because an alert has to be answerable during
 launch and migration, before the application has a scene, and because a sheet
 has to attach to a window SwiftUI does not own. */
@MainActor
struct SystemAlertPresenter: AlertPresenter {
	/// Cancelling the task that awaits the answer takes the alert down, and it
	/// answers with its Escape button.
	func present(_ request: AlertRequest, in presentation: AlertPresentation) async -> AlertPresenterResult {
		guard Task.isCancelled == false else {
			return AlertPresenterResult(response: request.escapeButton, suppressionChecked: false)
		}

		// The unit-test host never takes the foreground, so a main-window alert
		// would fall through to a blocking modal and hang the suite.
		if ApplicationForeground.mode.takesForeground == false, presentation == .mainWindow,
		   SheetPresentation.hostWindow?.isVisible != true
		{
			return AlertPresenterResult(response: request.escapeButton, suppressionChecked: false)
		}

		guard let parent = sheetParent(for: presentation) else {
			return presentModal(request)
		}

		let session = AlertSession(request: request)

		return await withTaskCancellationHandler {
			await session.beginSheet(on: parent)
		} onCancel: {
			Task { @MainActor in session.cancel() }
		}
	}

	/// The blocking form, for launch and migration: before the application has
	/// a scene there is no window to attach a sheet to.
	private func presentModal(_ request: AlertRequest) -> AlertPresenterResult {
		AlertSession(request: request).runModal()
	}

	/** The window an alert attaches its sheet to, or nil when it has to run in
	 its own modal loop.

	 A hidden main window must not start a nested modal loop, so an explicit user
	 action reveals it first. The sheet goes on whatever that window is already
	 showing, because a sheet raised on a window with a sheet up would otherwise
	 wait behind it. */
	private func sheetParent(for presentation: AlertPresentation) -> NSWindow? {
		if let host = SheetPresentation.hostWindow, host.isVisible == false {
			let revealMainWindow = presentation == .mainWindow
				|| NSApp.windows.contains(where: \.isVisible) == false

			if revealMainWindow {
				ApplicationForeground.bringForward(host)
			}
		}

		if let hostWindow = SheetPresentation.hostWindow, hostWindow.isVisible {
			return hostWindow.frontmostAttachedSheet
		}

		guard presentation == .anyVisibleWindow else {
			return nil
		}

		let visibleWindow = NSApp.keyWindow.flatMap { $0.isVisible ? $0 : nil }
			?? NSApp.windows.first(where: \.isVisible)

		return visibleWindow?.frontmostAttachedSheet
	}
}

/** One showing of one alert.

 A class because the sheet has to be reachable after it is up: a cancelled task
 takes it down, and the answer arrives on a completion handler rather than as a
 return value. */
@MainActor
private final class AlertSession {
	private let request: AlertRequest
	private let alert: NSAlert
	/// Which response each button carries, in the order they were added, so a
	/// request with a third button but no second one still answers `.other`.
	private var buttonResponses: [AlertResponse] = []
	private var parent: NSWindow?
	private var hasAnswered = false
	/// The field a request with one is answered in: plain text, or a secure
	/// field that turns on Secure Event Input while it is focused.
	private var field: NSTextField?
	private var escapeRoute: EscapeKeyRoute?

	init(request: AlertRequest) {
		self.request = request
		alert = NSAlert()
		configure()
	}

	func runModal() -> AlertPresenterResult {
		beginEscapeRoute()
		let code = alert.runModal()
		endEscapeRoute()
		return result(for: code)
	}

	func beginSheet(on parent: NSWindow) async -> AlertPresenterResult {
		self.parent = parent
		beginEscapeRoute()

		let code = await withCheckedContinuation { continuation in
			alert.beginSheetModal(for: parent) { continuation.resume(returning: $0) }
		}

		hasAnswered = true
		endEscapeRoute()
		parentDidFinish()

		return result(for: code)
	}

	/** Takes the alert down unanswered, because whoever asked no longer waits.

	 It reads as the Escape button, the same as a sheet someone else ended. */
	func cancel() {
		guard hasAnswered == false, let parent else { return }

		parent.endSheet(alert.window, returnCode: .abort)
	}

	private func parentDidFinish() {
		parent = nil
	}

	private func configure() {
		alert.messageText = request.title
		alert.informativeText = request.body
		if let identifier = request.accessibilityIdentifier {
			alert.window.setAccessibilityIdentifier(identifier)
		}
		alert.alertStyle = switch request.style {
		case .informational: .informational
		case .warning: .warning
		case .critical: .critical
		}

		/* `NSAlert` lays its buttons out right to left in the order they are
		 added, with a third button on the far left, which is the order the
		 responses are named in. */
		addButton(request.defaultButton, as: .default)

		if let alternateButton = request.alternateButton {
			addButton(alternateButton, as: .alternate)
		}

		if let otherButton = request.otherButton {
			addButton(otherButton, as: .other)
		}

		if let requestedField = request.field {
			let field: NSTextField = switch requestedField {
			case let .text(placeholder, initialValue, _):
				Self.textField(placeholder: placeholder, value: initialValue)
			case let .secure(placeholder):
				Self.secureField(placeholder: placeholder)
			}
			field.setAccessibilityLabel(request.title)
			field.identifier = NSUserInterfaceItemIdentifier("alert-field")
			alert.accessoryView = field
			alert.window.initialFirstResponder = field
			self.field = field
		}

		if request.suppressionKey != nil {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = request.suppressionText ?? PromptStrings.Alert.doNotAskAgain
		}

		applyKeyEquivalents()
	}

	private static func textField(placeholder: String, value: String) -> NSTextField {
		let field = NSTextField(string: value)
		field.placeholderString = placeholder
		field.frame = NSRect(x: 0, y: 0, width: 260, height: field.fittingSize.height)
		return field
	}

	private static func secureField(placeholder: String) -> NSTextField {
		let field = NSSecureTextField(string: "")
		field.placeholderString = placeholder
		field.frame = NSRect(x: 0, y: 0, width: 260, height: field.fittingSize.height)
		return field
	}

	private func addButton(_ title: String, as response: AlertResponse) {
		let button = alert.addButton(withTitle: title)
		if let identifier = request.accessibilityIdentifier {
			button.setAccessibilityIdentifier(AccessibilityIdentifier.alertButton(identifier, response))
		}

		button.hasDestructiveAction = switch request.destructiveButton {
		case .default: response == .default
		case .alternate: response == .alternate
		case nil: false
		}

		buttonResponses.append(response)
	}

	/** Which button Return and Escape press.

	 `NSAlert` gives Return to the first button it was handed and Escape to a
	 button titled "Cancel", neither of which is the promise an `AlertRequest`
	 makes: Return is never the destructive button, and Escape answers whichever
	 button the request names as the way out whatever it is called.

	 A button carries one key equivalent. Where Return and Escape press the
	 same button -- a notice, or a security question whose Return is its way
	 out -- the button takes Return, which also draws it as the default, and
	 Escape and Command-period reach it through ``EscapeKeyRoute``. */
	private func applyKeyEquivalents() {
		let returnButton = request.returnButton

		for (index, button) in alert.buttons.enumerated() {
			let response = buttonResponses[index]

			button.keyEquivalent = if response == returnButton {
				"\r"
			} else if response == request.escapeButton {
				"\u{1b}"
			} else {
				""
			}
		}
	}

	/// Starts routing Escape to the button that already holds Return, while
	/// the alert is up.
	private func beginEscapeRoute() {
		guard request.returnIsEscape,
		      let index = buttonResponses.firstIndex(of: request.escapeButton)
		else { return }
		let button = alert.buttons[index]
		escapeRoute = EscapeKeyRoute(window: alert.window) { [weak button] in
			button?.performClick(nil)
		}
	}

	private func endEscapeRoute() {
		escapeRoute?.end()
		escapeRoute = nil
	}

	private func result(for code: NSApplication.ModalResponse) -> AlertPresenterResult {
		let result = AlertPresenterResult(
			response: resolvedResponse(code),
			suppressionChecked: alert.suppressionButton?.state == .on,
			text: field?.stringValue
		)
		/* A secret is handed to whoever asked and to nothing else: the field
		 does not keep it after the alert is gone. */
		field?.stringValue = ""
		return result
	}

	/** A modal session or a sheet someone else ended -- `abort` or `stop` while
	 the application is quitting, say -- never answered the question, so it
	 reads as the cancel button instead of silently agreeing to the default. */
	private func resolvedResponse(_ code: NSApplication.ModalResponse) -> AlertResponse {
		let index = code.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

		guard buttonResponses.indices.contains(index) else {
			return request.escapeButton
		}

		return buttonResponses[index]
	}
}

/** Presses the way out when Escape or Command-period is typed in one window.

 The system answers those keys with the button whose key equivalent is Escape.
 An alert whose way out also holds Return has no such button, so this stands in
 for it, for as long as the alert is up and only in the alert's own window. */
@MainActor
final class EscapeKeyRoute {
	private var monitor: Any?

	/// `press` clicks the button Escape stands for.
	init(window: NSWindow, press: @escaping @MainActor () -> Void) {
		monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
			guard let window, event.window === window, Self.isCancelKey(event) else {
				return event
			}
			press()
			return nil
		}
	}

	func end() {
		if let monitor {
			NSEvent.removeMonitor(monitor)
		}
		monitor = nil
	}

	/// Escape, or Command-period, the other key that means "cancel" on macOS.
	static func isCancelKey(_ event: NSEvent) -> Bool {
		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		switch event.charactersIgnoringModifiers {
		case "\u{1b}": return modifiers.subtracting(.function).isEmpty
		case ".": return modifiers == .command
		default: return false
		}
	}
}
