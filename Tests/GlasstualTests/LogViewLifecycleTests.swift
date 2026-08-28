/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Log view lifecycle")
struct LogViewLifecycleTests {
	@Test("A web view that finishes loading after its client has gone is ignored")
	func lateWebViewFinishedLoadingIsIgnoredAfterWeakClientDeallocation() throws {
		var client: IRCClient? = IRCClient(config: ClientConfig())
		let window = TVCMainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = try LogController(
			client: #require(client),
			in: window
		)
		let logView = try #require(controller.backingView)
		weak let weakClient = client

		client = nil

		#expect(weakClient == nil)
		#expect(controller.viewIsLoaded == false)

		logView.informDelegateWebViewFinishedLoading()

		#expect(controller.viewIsLoaded == false)
	}

	@Test("A web view that calls back after its controller has gone is ignored")
	func lateWebViewCallbacksAreIgnoredAfterControllerDeallocation() throws {
		let client = IRCClient(config: ClientConfig())
		let window = TVCMainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		var controller: LogController? = LogController(client: client, in: window)
		let logView = try #require(controller?.backingView)
		weak let weakController = controller

		controller = nil

		#expect(weakController == nil)
		#expect(logView.viewController == nil)

		logView.informDelegateWebViewFinishedLoading()
		logView.informDelegateWebViewClosedUnexpectedly()
	}
}
