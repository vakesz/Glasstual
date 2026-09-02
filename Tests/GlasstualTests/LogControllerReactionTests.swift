/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/// A reaction arrives for a line that is already drawn, so recording it is only
/// half the job: the transcript has to be told, or the reaction stays invisible
/// until the view is cleared and history reloaded.
@MainActor
@Suite("Live message reactions", .serialized)
struct LogControllerReactionTests {
	private func textView(in root: NSView) -> NSTextView? {
		root.subviews.lazy.compactMap { view in
			(view as? NSTextView) ?? textView(in: view)
		}.first
	}

	/** Waits for the controller to finish the work it started on its own.

	 The initial history load is a standalone pipeline job, so draining the
	 batched chain does not wait for it, and until it has been applied every
	 printed line is held in the projection's replay buffer. */
	private func settle(_ controller: LogController, until isReady: () -> Bool) async {
		for _ in 0 ..< 200 {
			await controller.drainRenderJobs()
			if isReady() {
				return
			}
			try? await Task.sleep(for: .milliseconds(10))
		}
	}

	@Test("A reaction to a line already on screen is drawn without a history reload")
	func reactionReachesTheTranscript() async throws {
		/* The transcript only draws live lines once the initial history load has
		 finished; loading it lazily waits for a visible view, which a headless
		 window never becomes. */
		let lazyHistory = Preferences.Logging.loadHistoryLazily
		let wasLazy = lazyHistory.value
		lazyHistory.value = false
		defer { lazyHistory.value = wasLazy }

		let client = IRCClient(config: ClientConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		let controller = window.logControllers.controller(for: client)
		let logView = controller.ensureBackingView()
		logView.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = logView.view
		await controller.drainRenderJobs()

		var line = LogLine()
		line.messageBody = "shipping it"
		line.lineType = .privateMessage
		line.nickname = "alice"
		line.messageIdentifier = "msg-\(UUID().uuidString)"
		controller.print(line)

		let transcript = try #require(textView(in: logView.view))
		await settle(controller) { transcript.string.contains("shipping it") }
		try #require(transcript.string.contains("shipping it"))

		try controller.noteReaction(
			"\u{1f44d}",
			fromNickname: "bob",
			toMessageIdentifier: #require(line.messageIdentifier)
		)
		await settle(controller) { transcript.string.contains("\u{1f44d} 1") }

		#expect(transcript.string.contains("\u{1f44d} 1"))
	}
}
