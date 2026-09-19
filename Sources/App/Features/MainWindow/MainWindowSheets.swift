// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Observation
import os
import SwiftUI

private let mainWindowSheetLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "MainWindowSheets"
)

/** Everything the main window raises in front of itself.

 Not the window's own presentation -- the columns are that -- but the
 presentations it happens to host: the sheet chain its features and the shared
 alerts attach to, the input prompt, the file chooser a transfer offer opens and
 the settings archive's import and export. They share one owner because they
 share one rule: only the outermost of them is ever the window's, and each of the
 rest belongs to whatever raised it. */
@MainActor
@Observable
final class MainWindowSheetModel {
	/// The outermost sheet the window is showing; each one holds whatever it
	/// raised on top of itself.
	private(set) var presentedSheet: MainWindowSheet?
	var inputPrompt: InputPromptPresentation?
	var isChoosingTransferFiles = false
	let settingsTransfer = MainWindowSettingsTransferModel()

	@ObservationIgnored private var transferFileSelection: (([URL]) -> Void)?

	// MARK: - The sheet chain

	/// Raises a sheet: the first one on the window, any after it on whichever
	/// sheet is innermost.
	func presentSheet(_ presentation: MainWindowSheet) {
		guard let innermost = presentedSheet?.chain.last else {
			presentedSheet = presentation
			return
		}
		innermost.child = presentation
	}

	func dismissSheet(ownedBy owner: AnyObject) {
		closeSheets { $0 === owner }
	}

	func dismissPresentedSheet() {
		dismiss(presentedSheet)
	}

	func closeSheets(where shouldClose: (AnyObject) -> Bool) {
		dismiss(presentedSheet?.chain.first { shouldClose($0.owner) })
	}

	/// Takes `presentation` down, and everything it raised with it.
	func dismiss(_ presentation: MainWindowSheet?) {
		guard let presentation else { return }
		if presentedSheet === presentation {
			presentedSheet = nil
		} else {
			presentedSheet?.chain.first { $0.child === presentation }?.child = nil
		}
		presentation.finish()
	}

	// MARK: - Input prompts

	func presentInputPrompt(
		_ request: InputPromptRequest,
		completion: @escaping @MainActor (InputPromptOutcome) -> Void
	) {
		inputPrompt?.finish(.cancelled)
		inputPrompt = InputPromptPresentation(request: request, completion: completion)
	}

	func completeInputPrompt(_ outcome: InputPromptOutcome) {
		guard let inputPrompt else { return }
		inputPrompt.finish(outcome)
		self.inputPrompt = nil
	}

	func inputPromptDidDismiss() {
		guard let inputPrompt else { return }
		inputPrompt.finish(.cancelled)
		self.inputPrompt = nil
	}

	// MARK: - Choosing files to send

	func chooseTransferFiles(perform: @escaping ([URL]) -> Void) {
		transferFileSelection = perform
		isChoosingTransferFiles = true
	}

	func completeTransferFileSelection(_ result: Result<[URL], Error>) {
		defer { transferFileSelection = nil }
		switch result {
		case let .success(urls):
			transferFileSelection?(urls)
		case let .failure(error):
			mainWindowSheetLogger.error("Choosing files to transfer failed: \(error)")
		}
	}
}

/** One sheet the main window is showing, and whatever that sheet raised on top
 of itself.

 The chain is what makes a sheet-over-a-sheet work: SwiftUI presents a sheet
 from the view it is attached to, so a second one is presented by the first.
 This used to be an array the window indexed into, with two hand-written
 `Binding<Bool>` shims translating "is position N occupied" into a
 presentation and a host that recursed on `index + 1`. */
@MainActor
@Observable
final class MainWindowSheet: Identifiable {
	let id = UUID()
	let owner: AnyObject
	let content: AnyView
	/// The sheet this one raised, if any. Written by the sheet model, which is
	/// what keeps the chain and the owners in step.
	var child: MainWindowSheet?

	@ObservationIgnored private var didFinish = false
	@ObservationIgnored private let onDismiss: @MainActor () -> Void

	init(owner: AnyObject, content: some View, onDismiss: @escaping @MainActor () -> Void) {
		self.owner = owner
		self.content = AnyView(content)
		self.onDismiss = onDismiss
	}

	/// This sheet and everything above it, outermost first.
	var chain: [MainWindowSheet] {
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

/// Draws one sheet of the chain, and attaches the next one to it.
struct MainWindowSheetHost: View {
	let model: MainWindowSheetModel
	@Bindable var presentation: MainWindowSheet

	var body: some View {
		presentation.content
			/* Every hosted sheet is sized by its own content: `.fitted` asks for
			 the content's ideal size and leaves the user free to drag the sheet
			 anywhere between the content's minimum and maximum. */
			.presentationSizing(.fitted)
			.sheet(item: child) { nested in
				MainWindowSheetHost(model: model, presentation: nested)
			}
	}

	private var child: Binding<MainWindowSheet?> {
		Binding(
			get: { presentation.child },
			set: { nested in
				if nested == nil {
					model.dismiss(presentation.child)
				}
			}
		)
	}
}

/// A presentation whose lifetime follows one session: the window closes it when
/// that session goes away. Conformed to by sheets and by the two windows that
/// are also about one connection.
@MainActor
protocol SessionScoped: AnyObject {
	var sessionId: String? { get }
}

/// A presentation whose lifetime follows one channel, and through it one session.
@MainActor
protocol ChannelScoped: SessionScoped {
	var channelId: String? { get }
}

/** Owns one state-driven SwiftUI sheet attached to the application's main
 window. A feature subclasses this to keep validation and the closure it
 reports through beside the model it coordinates; the base owns no AppKit
 view. */
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
		mainWindow.sheetModel.presentSheet(MainWindowSheet(
			owner: self,
			content: content,
			onDismiss: { [weak self] in self?.sheetDidEnd() }
		))
	}

	func endSheet() {
		window?.sheetModel.dismissSheet(ownedBy: self)
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
