// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

/// The main window's columns: the widths they open at and the room the
/// window keeps for them.
@MainActor
@Suite("Main window column layout")
struct MainWindowColumnLayoutTests {
	private func descendants<View: NSView>(of type: View.Type, in root: NSView) -> [View] {
		root.subviews.flatMap { view in
			(view as? View).map { [$0] } ?? descendants(of: type, in: view)
		}
	}

	private func transcriptLine(_ text: String) -> TranscriptRow {
		TranscriptRow(
			lineNumber: UUID().uuidString,
			receivedAt: Date(),
			nickname: "alice",
			memberType: .normal,
			lineType: .privateMessage,
			command: "PRIVMSG",
			messageIdentifier: nil,
			replyToMessageIdentifier: nil,
			deliveryState: .none,
			deliveryFailureReason: nil,
			reactions: [:],
			markers: [],
			body: TranscriptBody(
				plainText: text,
				runs: [TranscriptTextRun(text: text)]
			)
		)
	}

	/** Turns the run loop until `isSettled`. SwiftUI applies a column's
	 presentation in a later transaction, and the split view animates it, so
	 a layout pass straight after a change still shows the old columns. */
	private func settle(until isSettled: () -> Bool) {
		let deadline = Date.now.addingTimeInterval(5)
		repeat {
			RunLoop.main.run(until: Date.now.addingTimeInterval(0.02))
			if isSettled() {
				return
			}
		} while Date.now < deadline
	}

	private func frame(of view: NSView?, in root: NSView) -> NSRect {
		guard let view, view.isHiddenOrHasHiddenAncestor == false else { return .zero }
		return view.convert(view.bounds, to: root)
	}

	/// A main window with its own chrome and SwiftUI content, as the
	/// application delegate builds it, with the loading screen out of the way.
	private func makeMainWindow() -> MainWindow {
		let window = MainWindow(
			contentRect: NSRect(origin: .zero, size: MainWindowConstants.minimumContentSize),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentMinSize = MainWindowConstants.minimumContentSize
		window.configure()
		window.loadingScreen.hide()
		return window
	}

	/** The columns open at the widths the reader left them at, with the
	 transcript between them and its last line clear of the input bar. A width
	 modifier the split view never sees leaves a column at SwiftUI's own
	 default: 144 points for the sidebar, 270 for an inspector.

	 Where the columns sit in a visible window at its narrowest, and that the
	 transcript takes its width back when the list closes, is checked against
	 the running app by the E2E harness's `MainWindowColumnsCheck`. A test
	 host's window presents the inspector beside the detail column rather
	 than over it, and grows to hold it. */
	@Test("The columns open at their stored widths around the transcript")
	func columnsOpenAtStoredWidths() throws {
		let sidebarKey = SettingsKeys.MainWindow.sidebarWidth
		let memberListKey = SettingsKeys.MainWindow.memberListWidth
		let stored = (sidebarKey.value, memberListKey.value)
		defer {
			sidebarKey.value = stored.0
			memberListKey.value = stored.1
		}
		// Neither is SwiftUI's own default, so each proves its column read it.
		sidebarKey.value = 200
		memberListKey.value = 210

		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig())
		let channel = fixture.chatSession.createConversation(
			with: ConversationConfig.seed(withName: "#swift"),
			on: session,
			add: true,
			adjust: false,
			reload: false
		)
		let window = makeMainWindow()
		let transcript = window.transcriptControllers.controller(for: channel).ensureBackingView()
		window.columnModel.transcript = transcript
		transcript.setTopic("Native AppKit discussion")
		transcript.replaceLines([transcriptLine("hello there")])
		window.columnModel.setMemberListVisible(true)
		window.columnModel.applyMemberListAvailability(true)
		let root = try #require(window.contentView)
		var sidebar: NSView? {
			descendants(of: SidebarOutlineView.self, in: root).first?.enclosingScrollView
		}
		var memberList: NSView? {
			descendants(of: MemberListNativeTable.self, in: root).first?.enclosingScrollView
		}
		settle {
			transcript.window != nil && frame(of: sidebar, in: root).width > 0
				&& frame(of: memberList, in: root).width > 0
		}

		let sidebarFrame = frame(of: sidebar, in: root)
		let listFrame = frame(of: memberList, in: root)
		let transcriptFrame = transcript.convert(transcript.bounds, to: root)
		#expect(abs(sidebarFrame.width - 200) < 1, "sidebar \(sidebarFrame)")
		#expect(abs(listFrame.width - 210) < 1, "member list \(listFrame)")
		#expect(transcriptFrame.minX >= sidebarFrame.maxX - 0.5, "transcript \(transcriptFrame) sidebar \(sidebarFrame)")
		#expect(transcriptFrame.maxX <= listFrame.minX + 0.5, "transcript \(transcriptFrame) member list \(listFrame)")
		#expect(
			transcriptFrame.width >= MainWindowConstants.conversationMinimumWidth,
			"transcript \(transcriptFrame)"
		)

		/* The bar floats over the transcript, and the inset is what keeps the
		 last line out from under it. */
		let scrollView = try #require(descendants(of: NSScrollView.self, in: transcript).first)
		let field = window.inputContentView.frame
		let barHeight = field.height + InputBarLayout.fieldVerticalPadding * 2
			+ InputBarLayout.bottomPadding
		let inset = scrollView.contentInsets.bottom
		#expect(abs(inset - barHeight) < 1, "inset \(inset) bar \(barHeight)")
	}

	/** Columns keep their widths while the window narrows, so the window may
	 not be made narrower than its open columns. A split view wider than its
	 window is laid out past the window's edges, and one that cannot fit at
	 all ends AppKit's constraint passes with an exception. */
	@Test("The window's minimum width follows its open columns")
	func windowMinimumFollowsOpenColumns() {
		let floor = MainWindowConstants.minimumContentSize
		let window = makeMainWindow()
		func minimumIs(_ width: CGFloat) -> Bool {
			abs(window.contentMinSize.width - width) < 0.5 && abs(window.contentMinSize.height - floor.height) < 0.5
		}
		window.columnModel.setMemberListVisible(true)
		window.columnModel.applyMemberListAvailability(true)
		window.columnModel.recordSidebarWidth(400)
		window.columnModel.recordMemberListWidth(500)
		#expect(minimumIs(400 + 400 + 500), "minimum \(window.contentMinSize)")

		// The hosting view resets the minimum as it lays out; the columns' stays.
		window.contentMinSize = .zero
		#expect(minimumIs(400 + 400 + 500), "minimum \(window.contentMinSize)")

		window.columnModel.setMemberListVisible(false)
		#expect(minimumIs(400 + 400), "minimum \(window.contentMinSize)")
		window.columnModel.isSidebarVisible = false
		#expect(minimumIs(floor.width), "minimum \(window.contentMinSize)")
	}
}
