/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import Observation
import SwiftUI

/** One sheet the main window is showing, and whatever that sheet raised on top
 of itself.

 The chain is what makes a sheet-over-a-sheet work: SwiftUI presents a sheet
 from the view it is attached to, so a second one is presented by the first.
 This used to be an array the window indexed into, with two hand-written
 `Binding<Bool>` shims translating "is position N occupied" into a
 presentation and a host that recursed on `index + 1`. */
@MainActor
@Observable
final class PresentedSheet: Identifiable {
	let id = UUID()
	let owner: AnyObject
	let content: AnyView
	/// The sheet this one raised, if any. Written by the presentation model,
	/// which is what keeps the chain and the owners in step.
	var child: PresentedSheet?

	@ObservationIgnored private var didFinish = false
	@ObservationIgnored private let onDismiss: @MainActor () -> Void

	init(owner: AnyObject, content: some View, onDismiss: @escaping @MainActor () -> Void) {
		self.owner = owner
		self.content = AnyView(content)
		self.onDismiss = onDismiss
	}

	/// This sheet and everything above it, outermost first.
	var chain: [PresentedSheet] {
		[self] + (child?.chain ?? [])
	}

	/// Tells the owners their sheets are gone, the innermost first.
	func finish() {
		child?.finish()
		child = nil
		guard didFinish == false else { return }
		didFinish = true
		onDismiss()
	}
}

/// Owns one state-driven SwiftUI sheet attached to the application's main
/// window. Feature sessions subclass this to keep validation and delegate
/// callbacks beside the model they coordinate; the base owns no AppKit view.
@MainActor
class SheetSession: NSObject {
	weak var delegate: AnyObject?
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
		mainWindow.presentationModel.presentSheet(PresentedSheet(
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
		presentationModel.presentSheet(PresentedSheet(owner: owner, content: content, onDismiss: onDismiss))
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
