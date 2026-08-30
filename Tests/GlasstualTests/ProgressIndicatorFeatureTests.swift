/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
private final class ProgressIndicatorParentWindowSpy: NSWindow {
	private(set) var begunSheet: NSWindow?
	private(set) var endedSheet: NSWindow?

	private var completionHandler: ((NSApplication.ModalResponse) -> Void)?

	override func beginSheet(
		_ sheetWindow: NSWindow,
		completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil
	) {
		begunSheet = sheetWindow
		completionHandler = handler
	}

	override func endSheet(_ sheetWindow: NSWindow) {
		endedSheet = sheetWindow
		completionHandler?(.cancel)
		completionHandler = nil
	}
}

@MainActor
@Suite("Progress indicator sheet")
struct ProgressIndicatorFeatureTests {
	@Test("The sheet copy comes from the localized catalog entries")
	func contentPreservesLocalizedStatusMessage() {
		let content = ProgressIndicatorContent.current

		#expect(content.statusMessage == "Please wait a moment while this task is completed…")
		#expect(content.windowTitle == "Task in Progress")
	}

	@Test("Starting and stopping the model is repeatable and idempotent")
	func modelTracksRepeatablePresentationLifecycle() {
		let model = ProgressIndicatorModel()

		#expect(model.phase == .idle)
		#expect(model.isRunning == false)

		model.start()
		model.start()
		#expect(model.phase == .running)
		#expect(model.isRunning)

		model.stop()
		model.stop()
		#expect(model.phase == .idle)
		#expect(model.isRunning == false)
	}

	@Test("The adapter hosts SwiftUI and drives the parent window's sheet lifecycle")
	func adapterHostsSwiftUIAndUsesParentWindowSheetLifecycle() throws {
		let parentWindow = ProgressIndicatorParentWindowSpy()
		let adapter = ProgressIndicatorSheet(window: parentWindow)
		let hostingView = try #require(adapter.sheet.contentView as? NSHostingView<ProgressIndicatorView>)

		#expect(adapter.window === parentWindow)
		#expect(hostingView.rootView.model.phase == .idle)
		#expect(adapter.sheet.styleMask.contains(.resizable) == false)
		#expect(adapter.sheet.isReleasedWhenClosed == false)
		#expect(adapter.sheet.isRestorable == false)
		#expect(adapter.sheet.tabbingMode == .disallowed)
		#expect(adapter.sheet.contentMinSize == NSSize(width: 406, height: 60))
		#expect(adapter.sheet.contentMaxSize == NSSize(width: 406, height: 60))

		adapter.start()
		#expect(parentWindow.begunSheet === adapter.sheet)
		#expect(hostingView.rootView.model.phase == .running)

		adapter.stop()
		#expect(parentWindow.endedSheet === adapter.sheet)
		#expect(hostingView.rootView.model.phase == .idle)
	}
}
