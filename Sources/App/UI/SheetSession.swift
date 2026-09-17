// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// Owns one state-driven SwiftUI sheet attached to the application's main
/// window. A feature subclasses this to keep validation and the closure it
/// reports through beside the model it coordinates; the base owns no AppKit
/// view.
@MainActor
class SheetSession: NSObject {
	weak var window: MainWindow?
	private var content: AnyView?

	@available(*, unavailable)
	override init() {
		fatalError("init() is unavailable; use init(window:)")
	}

	init(window: MainWindow?) {
		self.window = window
		super.init()
	}

	func setContent(_ content: some View) {
		self.content = AnyView(content)
	}

	func startSheet() {
		guard let content, let mainWindow = window ?? AppServices.delegate.mainWindow else { return }
		window = mainWindow
		mainWindow.presentationModel.presentSheet(MainWindowSheet(
			owner: self,
			content: content,
			onDismiss: { [weak self] in self?.sheetDidEnd() }
		))
	}

	func endSheet() {
		window?.presentationModel.dismissSheet(ownedBy: self)
	}

	/// The sheet has left the window, however it went.
	func sheetDidEnd() {}

	/// The user accepted the sheet.
	func submit() {
		endSheet()
	}

	/// The sheet is going away without being accepted.
	func cancel() {
		endSheet()
	}
}

/// Shared alerts and prompts appear on the main window, in the same
/// state-driven sheet stack its own sheets use.
extension MainWindow: SheetPresentationHost {
	var sheetHostWindow: NSWindow {
		self
	}

	func presentSheet(owner: AnyObject, content: AnyView, onDismiss: @escaping @MainActor () -> Void) {
		presentationModel.presentSheet(MainWindowSheet(owner: owner, content: content, onDismiss: onDismiss))
	}

	func dismissSheet(ownedBy owner: AnyObject) {
		presentationModel.dismissSheet(ownedBy: owner)
	}

	func presentInputPrompt(
		_ request: InputPromptRequest,
		completion: @escaping @MainActor (InputPromptOutcome) -> Void
	) {
		presentationModel.presentInputPrompt(request, completion: completion)
	}
}
