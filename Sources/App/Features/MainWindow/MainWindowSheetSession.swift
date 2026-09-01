/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MainWindowSheetPresentation: Identifiable {
	let id = UUID()
	let owner: AnyObject
	let content: AnyView

	@ObservationIgnored private var didFinish = false
	@ObservationIgnored private let onDismiss: () -> Void

	init(owner: AnyObject, content: some View, onDismiss: @escaping () -> Void) {
		self.owner = owner
		self.content = AnyView(content)
		self.onDismiss = onDismiss
	}

	func finish() {
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
			onDismiss: { [weak self] in self?.sheetDidEnd(withReturnCode: 0) }
		))
	}

	public func endSheet() {
		window?.presentationModel.dismissSheet(ownedBy: self)
	}

	open func sheetDidEnd(withReturnCode _: Int) {}

	open func ok(_: Any?) {
		endSheet()
	}

	open func cancel(_: Any?) {
		endSheet()
	}

	open func close() {
		cancel(nil)
	}
}
