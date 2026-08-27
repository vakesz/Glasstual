/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import XCTest

@MainActor
final class LogViewLifecycleTests: XCTestCase {
	func testLateWebViewFinishedLoadingIsIgnoredAfterWeakClientDeallocation() throws {
		var client: IRCClient? = IRCClient(configDictionary: [:])
		let window = TVCMainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = try LogController(
			client: XCTUnwrap(client),
			in: window
		)
		let logView = try XCTUnwrap(controller.backingView)
		weak let weakClient = client

		client = nil

		XCTAssertNil(weakClient)
		XCTAssertFalse(controller.viewIsLoaded)

		logView.informDelegateWebViewFinishedLoading()

		XCTAssertFalse(controller.viewIsLoaded)
	}

	func testLateWebViewCallbacksAreIgnoredAfterControllerDeallocation() throws {
		let client = IRCClient(configDictionary: [:])
		let window = TVCMainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		var controller: LogController? = LogController(client: client, in: window)
		let logView = try XCTUnwrap(controller?.backingView)
		weak let weakController = controller

		controller = nil

		XCTAssertNil(weakController)
		XCTAssertNil(logView.viewController)

		logView.informDelegateWebViewFinishedLoading()
		logView.informDelegateWebViewClosedUnexpectedly()
	}
}
