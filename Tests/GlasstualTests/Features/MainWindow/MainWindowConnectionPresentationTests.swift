// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Main window connection controls")
struct MainWindowConnectionPresentationTests {
	@Test("Connection row and window title share phase and available actions")
	func phases() throws {
		let session = TestServerSession()
		#expect(MainWindowConnectionPresentation(session: session)?.actions == [.connect])
		session.reconnect.timer.start(3600, repeats: false)
		defer { session.reconnect.timer.stop() }
		let waiting = try #require(MainWindowConnectionPresentation(session: session))
		#expect(waiting.status == .waitingToReconnect)
		#expect(waiting.actions == [.connect, .cancelReconnect])
		#expect(MainWindowTitleContent(session: session, conversation: nil).subtitle.hasPrefix(waiting.status.title))
		session.isConnecting = true
		#expect(MainWindowConnectionPresentation(session: session)?.actions == [.disconnect])
		session.isConnecting = false
		session.isConnected = true
		#expect(MainWindowConnectionPresentation(session: session)?.status == .loggingOn)
		session.isLoggedIn = true
		#expect(MainWindowConnectionPresentation(session: session) == nil)
		session.isDisconnecting = true
		#expect(MainWindowConnectionPresentation(session: session)?.actions == [])
		session.isTerminating = true
		#expect(MainWindowConnectionPresentation(session: session) == nil)
	}

	@Test("An action from the previous selection cannot cancel another server's retry")
	func staleSelection() throws {
		let first = TestServerSession()
		let second = TestServerSession()
		first.reconnect.timer.start(3600, repeats: false)
		second.reconnect.timer.start(3600, repeats: false)
		defer {
			first.reconnect.timer.stop()
			second.reconnect.timer.stop()
		}
		let presentation = try #require(MainWindowConnectionPresentation(session: first))
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		window.selectedItem = second
		presentation.perform(.cancelReconnect, in: window, commands: MenuActionController())
		#expect(first.isReconnecting)
		#expect(second.isReconnecting)
	}

	@Test("A narrow member rail yields space and restores its preferred width")
	func railFitsAvailableSpace() {
		let minimum = MainWindowConstants.conversationMinimumWidth + MemberListLayout.handleWidth
		#expect(MainWindowMemberRail.effectiveWidth(preferred: 260, available: minimum + 159) == nil)
		#expect(MainWindowMemberRail.effectiveWidth(preferred: 260, available: minimum + 160) == 160)
		#expect(MainWindowMemberRail.effectiveWidth(preferred: 260, available: minimum + 210) == 210)
		#expect(MainWindowMemberRail.effectiveWidth(preferred: 260, available: minimum + 400) == 260)
		#expect(MainWindowMemberRail.effectiveWidth(preferred: 100, available: minimum + 400) == 160)
	}
}
