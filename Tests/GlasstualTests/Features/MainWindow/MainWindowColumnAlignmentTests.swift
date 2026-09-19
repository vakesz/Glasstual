// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

/** Where the conversation and the member list begin, under a transparent
 titlebar.

 The two columns are built by different frameworks: the transcript is an AppKit
 scroll view inside an `NSViewRepresentable`, which SwiftUI lays out inside the
 safe area, and the member list is a SwiftUI `List` whose own scroll view runs
 the full height of the window and insets its rows by the titlebar instead.
 Those are two ways of reaching the same line, and the reader sees them side by
 side, so the line is what this measures. */
@MainActor
@Suite("Main window column alignment")
struct MainWindowColumnAlignmentTests {
	private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
		root.subviews.flatMap { view in
			(view as? View).map { [$0] } ?? descendants(of: type, in: view)
		}
	}

	@Test("The transcript and the member list start their content on the same line")
	func columnsStartAtTheSafeAreaTop() throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: [.titled, .fullSizeContentView],
			backing: .buffered,
			defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		let transcriptView = controller.ensureBackingView()
		let memberList = MemberList()
		let host = NSHostingController(rootView: HStack(spacing: 0) {
			TranscriptViewRepresentable(transcriptView: transcriptView)
			MemberListView(model: memberList, redirectTyping: { _ in })
				.scrollEdgeEffectStyle(.soft, for: .top)
				.frame(width: 200)
		})
		host.preferredContentSize = NSSize(width: 800, height: 600)
		window.contentViewController = host
		window.setContentSize(NSSize(width: 800, height: 600))
		window.contentView?.layoutSubtreeIfNeeded()
		host.view.layoutSubtreeIfNeeded()

		/* The hosting view is flipped, so the safe area's top inset is the
		 distance from the top of the column to the first line either may draw
		 on. A window with no titlebar to hide under would make the whole test
		 vacuous. */
		let safeTop = host.view.safeAreaInsets.top
		#expect(safeTop > 0)

		let transcript = transcriptView.scrollView
		let transcriptFrame = transcript.convert(transcript.bounds, to: host.view)
		#expect(abs(transcriptFrame.minY - safeTop) < 0.5, "transcript at \(transcriptFrame)")
		/* Its insets are the input bar's, set by hand; nothing adjusts them for
		 the titlebar, and nothing may start doing so. */
		#expect(transcript.automaticallyAdjustsContentInsets == false)
		#expect(transcript.contentInsets.top == 0)

		let list = try #require(
			descendants(of: NSScrollView.self, in: host.view).first { $0 !== transcript }
		)
		let listFrame = list.convert(list.bounds, to: host.view)
		#expect(abs(listFrame.minY + list.contentInsets.top - safeTop) < 0.5, "list at \(listFrame)")
	}
}
