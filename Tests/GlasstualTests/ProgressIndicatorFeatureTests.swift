/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import SwiftUI
import XCTest

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
final class ProgressIndicatorFeatureTests: XCTestCase {
	func testContentPreservesLocalizedStatusMessage() {
		let content = ProgressIndicatorContent.current

		XCTAssertEqual(content.statusMessage, "Please wait a moment while this task is completed…")
		XCTAssertEqual(content.windowTitle, "Task in Progress")
	}

	func testModelTracksRepeatablePresentationLifecycle() {
		let model = ProgressIndicatorModel()

		XCTAssertEqual(model.phase, .idle)
		XCTAssertFalse(model.isRunning)

		model.start()
		model.start()
		XCTAssertEqual(model.phase, .running)
		XCTAssertTrue(model.isRunning)

		model.stop()
		model.stop()
		XCTAssertEqual(model.phase, .idle)
		XCTAssertFalse(model.isRunning)
	}

	func testRuntimeSheetContractSurvivesWithoutANib() {
		XCTAssertEqual(NSStringFromClass(ProgressIndicatorSheet.self), "TDCProgressIndicatorSheet")
		XCTAssertNil(Bundle.main.path(forResource: "TDCProgressIndicatorSheet", ofType: "nib"))

		for selectorName in ["initWithWindow:", "start", "stop", "close", "cancel:"] {
			XCTAssertTrue(
				ProgressIndicatorSheet.instancesRespond(to: NSSelectorFromString(selectorName)),
				selectorName
			)
		}
	}

	func testAdapterHostsSwiftUIAndUsesParentWindowSheetLifecycle() throws {
		let parentWindow = ProgressIndicatorParentWindowSpy()
		let adapter = ProgressIndicatorSheet(window: parentWindow)
		let hostingView = try XCTUnwrap(adapter.sheet.contentView as? NSHostingView<ProgressIndicatorView>)

		XCTAssertIdentical(adapter.window, parentWindow)
		XCTAssertEqual(hostingView.rootView.model.phase, .idle)
		XCTAssertFalse(adapter.sheet.styleMask.contains(.resizable))
		XCTAssertFalse(adapter.sheet.isReleasedWhenClosed)
		XCTAssertFalse(adapter.sheet.isRestorable)
		XCTAssertEqual(adapter.sheet.tabbingMode, .disallowed)
		XCTAssertEqual(adapter.sheet.contentMinSize, NSSize(width: 406, height: 60))
		XCTAssertEqual(adapter.sheet.contentMaxSize, NSSize(width: 406, height: 60))

		adapter.start()
		XCTAssertIdentical(parentWindow.begunSheet, adapter.sheet)
		XCTAssertEqual(hostingView.rootView.model.phase, .running)

		adapter.stop()
		XCTAssertIdentical(parentWindow.endedSheet, adapter.sheet)
		XCTAssertEqual(hostingView.rootView.model.phase, .idle)
	}
}
