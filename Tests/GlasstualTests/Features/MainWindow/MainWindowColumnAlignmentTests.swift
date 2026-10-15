// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

/// Both native lists respect the titlebar safe area. The member table starts
/// below its persistent SwiftUI header and ends alongside the transcript.
@MainActor
@Suite("Main window column alignment")
struct MainWindowColumnAlignmentTests {
	@Test("Hiding the focused member table returns typing to the message field", arguments: [false, true])
	func hidingFocusedMemberListRestoresInput(selectionChanged: Bool) throws {
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		let table = MemberListNativeTable(frame: NSRect(x: 600, y: 0, width: 200, height: 600))
		/* A table with no column refuses first responder, and the window then
		 takes the focus itself, so the member column is load-bearing. */
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("member")))
		window.contentView?.addSubview(table)
		window.inputContentView.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
		window.contentView?.addSubview(window.inputContentView)
		window.inputContentView.configure()
		window.columnModel.applyMemberListAvailability(true)
		#expect(window.makeFirstResponder(table))
		try #require(window.firstResponder === table)

		if selectionChanged {
			window.columnModel.applyMemberListAvailability(false)
		} else {
			window.columnModel.setMemberListVisible(false)
		}

		#expect(window.firstResponder === window.inputContentView.textView)
	}

	private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
		root.subviews.flatMap { view in
			(view as? View).map { [$0] } ?? descendants(of: type, in: view)
		}
	}

	@Test("The transcript and member rail respect the safe area and fixed member header")
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
		#expect(listFrame.minY > safeTop, "The persistent member header needs room above the table")
		#expect(list.contentInsets.top == 0)
		#expect(abs(listFrame.maxY - transcriptFrame.maxY) < 0.5, "list at \(listFrame)")
	}
}
