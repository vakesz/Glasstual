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
	@Test("A loading transcript remains renderable while the host covers it")
	func loadingTranscriptIsNotHidden() {
		let client = IRCClient(config: ClientConfig())
		let window = TVCMainWindow(
			contentRect: .zero,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = LogController(client: client, in: window)
		let logView = controller.ensureBackingView()
		let host = MainWindowChannelView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

		#expect(logView.isLayingOutView)

		host.show(logView)

		#expect(logView.webView.isHidden == false)
	}

	@Test("Loading and navigation completion notify on the next actor turn")
	func duplicateCompletionSignalsAreCoalesced() {
		var state = LogViewLoadCompletionState()

		#expect(state.handle(.loadStarted) == .none)
		#expect(state.handle(.loadingChanged(false)) == .none)
		#expect(state.handle(.navigationFinished) == .schedule)
		#expect(state.handle(.loadingChanged(false)) == .none)
		#expect(state.handle(.scheduledCompletion) == .notify)
		#expect(state.handle(.scheduledCompletion) == .none)
	}

	@Test("A new navigation cancels a pending completion")
	func navigationCancelsPendingCompletion() {
		var state = LogViewLoadCompletionState()

		#expect(state.handle(.loadStarted) == .none)
		#expect(state.handle(.navigationFinished) == .schedule)
		#expect(state.handle(.navigationStarted) == .cancel)
		#expect(state.handle(.scheduledCompletion) == .none)
	}

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
		let logView = controller.ensureBackingView()
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
		let logView = try #require(controller?.ensureBackingView())
		weak let weakController = controller

		controller = nil

		#expect(weakController == nil)
		#expect(logView.viewController == nil)

		logView.informDelegateWebViewFinishedLoading()
		logView.informDelegateWebViewClosedUnexpectedly()
	}
}
