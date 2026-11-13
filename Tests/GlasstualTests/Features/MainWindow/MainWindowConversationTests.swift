// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Observation
import SwiftUI
import Synchronization
import Testing

@MainActor
@Suite("Main window conversation")
struct MainWindowConversationTests {
	/** An appearance change rebuilt the transcript representable by identity,
	 which moved the transcript into a new host and dropped the keyboard focus
	 and the reader's place with it. */
	@Test("An appearance change redraws the background and keeps the hosted transcript")
	func appearanceChangeKeepsTranscript() throws {
		let fixture = try SettingsTransferFixture()
		let source = ThemeAppearanceSource()
		let theme = source.makeStore(fixture)
		defer {
			fixture.cleanUp()
			AppServices.theme.appearanceDidChange()
		}
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		let columns = MainWindowColumnModel(theme: theme)
		let controller = TranscriptController(session: ServerSession(config: ServerConfig()), in: window)
		let transcriptView = controller.ensureBackingView()
		columns.transcript = transcriptView
		let hostingView = NSHostingView(rootView: MainWindowConversation(
			columns: columns,
			inputContentView: window.inputContentView
		))
		hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
		window.contentView = hostingView
		hostingView.layoutSubtreeIfNeeded()
		let host = try #require(transcriptView.superview as? TranscriptHostView)
		#expect(window.makeFirstResponder(transcriptView.textView))
		let redrawn = Mutex(false)
		let lightBackground = columns.conversationBackground
		withObservationTracking {
			_ = columns.conversationBackground
		} onChange: {
			redrawn.withLock { $0 = true }
		}

		source.appearance.isDark = true
		theme.appearanceDidChange()
		RunLoop.main.run(until: Date().addingTimeInterval(0.2))
		hostingView.layoutSubtreeIfNeeded()

		#expect(redrawn.withLock { $0 })
		#expect(columns.conversationBackground != lightBackground)
		#expect(transcriptView.superview === host)
		#expect(window.firstResponder === transcriptView.textView)
	}
}
