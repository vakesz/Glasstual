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

	init(request: AlertRequest) {
		self.request = request
		alert = NSAlert()
		configure()
	}

	func runModal() -> AlertPresenterResult {
		result(for: alert.runModal())
	}

	func beginSheet(on parent: NSWindow) async -> AlertPresenterResult {
		self.parent = parent

		let code = await withCheckedContinuation { continuation in
			alert.beginSheetModal(for: parent) { continuation.resume(returning: $0) }
		}

		hasAnswered = true
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
			case let .text(placeholder, initialValue):
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

	 Return wins where a request names one button as both, because a button
	 carries one key equivalent. Escape then does nothing, which is what the
	 system does with an alert that has no way out other than its own action,
	 and the reader reaches the same answer with Return. */
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
