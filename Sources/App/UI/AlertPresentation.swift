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
import SwiftUI

/** The window that carries alerts and input prompts in a sheet stack of its own.

 The main window presents sheets from SwiftUI state rather than through
 `beginSheet`, and that stack belongs to the main-window feature. Shared UI
 knows only this much of it, so an alert does not have to reach into the
 feature's presentation model to be shown there. */
@MainActor
protocol SheetPresentationHost: AnyObject {
	/// The window the sheets attach to, asked whether it is on screen.
	var sheetHostWindow: NSWindow { get }
	/// Raises `content` on top of whatever the host is already showing.
	/// `onDismiss` runs once the sheet has gone, however it went.
	func presentSheet(owner: AnyObject, content: AnyView, onDismiss: @escaping @MainActor () -> Void)
	/// Takes down the sheet `owner` raised, and anything raised on top of it.
	func dismissSheet(ownedBy owner: AnyObject)
	func presentInputPrompt(
		_ request: InputPromptRequest,
		completion: @escaping @MainActor (InputPromptOutcome) -> Void
	)
}

/// Where alerts and prompts find the window that hosts them.
@MainActor
enum SheetPresentation {
	/// Installed by the application once its main window exists; `nil`
	/// before then, which is when an alert runs application modal.
	weak static var host: (any SheetPresentationHost)?
}

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

	func presentModal(_ request: AlertRequest) -> AlertPresenterResult {
		AlertSession(request: request).runModal()
	}

	/** The window an alert attaches its sheet to, or nil when it has to run in
	 its own modal loop.

	 A hidden main window must not start a nested modal loop, so an explicit user
	 action reveals it first. The sheet goes on whatever that window is already
	 showing, because a sheet raised on a window with a sheet up would otherwise
	 wait behind it. */
	private func sheetParent(for presentation: AlertPresentation) -> NSWindow? {
		guard presentation != .applicationModal else {
			return nil
		}

		if let host = SheetPresentation.host, host.sheetHostWindow.isVisible == false {
			let revealMainWindow = presentation == .mainWindow
				|| NSApp.windows.contains(where: \.isVisible) == false

			if revealMainWindow {
				host.sheetHostWindow.makeKeyAndOrderFront(nil)
				NSApp.activate()
			}
		}

		if let hostWindow = SheetPresentation.host?.sheetHostWindow, hostWindow.isVisible {
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

		if request.suppressionKey != nil {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = request.suppressionText ?? PromptStrings.Alert.doNotAskAgain
		}

		applyKeyEquivalents()
	}

	private func addButton(_ title: String, as response: AlertResponse) {
		let button = alert.addButton(withTitle: title)

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
		AlertPresenterResult(
			response: resolvedResponse(code),
			suppressionChecked: alert.suppressionButton?.state == .on
		)
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
