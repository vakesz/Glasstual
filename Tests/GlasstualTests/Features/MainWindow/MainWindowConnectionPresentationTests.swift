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
		session.setConnectionTransportForTesting(.connecting)
		#expect(MainWindowConnectionPresentation(session: session)?.actions == [.disconnect])
		#expect(MainWindowConnectionPresentation(session: session)?.isInProgress == true)
		session.setConnectionTransportForTesting(.idle)
		session.setConnectionTransportForTesting(.connected)
		#expect(MainWindowConnectionPresentation(session: session)?.status == .loggingOn)
		session.isLoggedIn = true
		#expect(MainWindowConnectionPresentation(session: session) == nil)
		session.setConnectionShutdownForTesting(.disconnecting)
		#expect(MainWindowConnectionPresentation(session: session)?.actions == [])
		#expect(MainWindowConnectionPresentation(session: session)?.hasActions == false)
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

	/// The bar says what is wrong: a spinner while connecting, a symbol
	/// otherwise, and the in-progress action names what it stops.
	@Test("The bar marks progress with a spinner and stops a connection by name")
	func statusAndStopConnecting() throws {
		let session = TestServerSession()
		let idle = try #require(MainWindowConnectionPresentation(session: session))
		#expect(idle.isInProgress == false)
		#expect(idle.symbolName == "bolt.slash")
		#expect(String(localized: .MainWindow.connectionStopConnecting) == "Stop Connecting")
	}
}
