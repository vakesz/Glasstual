/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
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
final class MainWindowSheetPresentation: Identifiable {
	let id = UUID()
	let owner: AnyObject
	let content: AnyView
	/// The sheet this one raised, if any. Written by the presentation model,
	/// which is what keeps the chain and the owners in step.
	var child: MainWindowSheetPresentation?

	@ObservationIgnored private var didFinish = false
	@ObservationIgnored private let onDismiss: () -> Void

	init(owner: AnyObject, content: some View, onDismiss: @escaping () -> Void) {
		self.owner = owner
		self.content = AnyView(content)
		self.onDismiss = onDismiss
	}

	/// This sheet and everything above it, outermost first.
	var chain: [MainWindowSheetPresentation] {
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
open class MainWindowSheetSession: NSObject {
	public weak var delegate: AnyObject?
	public weak var window: MainWindow?
	private var content: AnyView?

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(window:)")
	}

	public init(window: MainWindow?) {
		self.window = window
		super.init()
	}

	public func setContent(_ content: some View) {
		self.content = AnyView(content)
	}

	public func startSheet() {
		guard let content, let mainWindow = window ?? AppController.shared.mainWindow else { return }
		window = mainWindow
		mainWindow.presentationModel.presentSheet(MainWindowSheetPresentation(
			owner: self,
			content: content,
			onDismiss: { [weak self] in self?.sheetDidEnd() }
		))
	}

	public func endSheet() {
		window?.presentationModel.dismissSheet(ownedBy: self)
	}

	/// The sheet has left the window, however it went.
	open func sheetDidEnd() {}

	/// The user accepted the sheet.
	open func submit() {
		endSheet()
	}

	/// The sheet is going away without being accepted.
	open func cancel() {
		endSheet()
	}
}
