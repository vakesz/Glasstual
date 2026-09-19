// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Main window title content")
struct MainWindowTitleContentTests {
	@Test("No selection uses the application identity without a subtitle")
	func noSelectionUsesApplicationIdentity() {
		let content = MainWindowTitleContent(session: nil, conversation: nil)

		#expect(content.title == ApplicationInfo.applicationName())
		#expect(content.subtitle.isEmpty)
	}

	@Test("A server selection composes status, nickname, and address in order")
	func serverSelectionComposition() {
		let session = TestServerSession()
		session.config.connectionName = "Libera"
		session.server = ServerEndpoint(serverAddress: "irc.example.test")
		session.userNickname = "Alice"

		let content = MainWindowTitleContent(session: session, conversation: nil)

		#expect(content.title == "Libera")
		#expect(content.subtitle == [
			MainWindowConnectionStatus.disconnected.title,
			"Alice",
			"irc.example.test",
		].joined(separator: " · "))
	}

	/** The subtitle is one line under a unified toolbar, so it truncates: it
	 used to carry status, network, nickname, member count and the channel's
	 mode string, and the mode string is what survived on a narrow window. */
	@Test("A channel selection carries its status, network and member count, and nothing else")
	func channelSelectionComposition() {
		let session = TestServerSession()
		session.config.connectionName = "Libera"
		session.userNickname = "Alice"
		let channel = Conversation(config: ConversationConfig(name: "#swift"))

		let content = MainWindowTitleContent(session: session, conversation: channel)

		#expect(content.title == "#swift")
		#expect(content.subtitle == [
			MainWindowConnectionStatus.disconnected.title,
			"Libera",
			MainWindowTitleContent.memberCount(0),
		].joined(separator: " · "))
	}

	/// The reader's own nickname belongs to the connection, so it is on the
	/// server row -- where the away marker is a format string rather than a
	/// catalog value beginning with a space.
	@Test("An away nickname is marked on the server row")
	func awayNicknameIsMarked() {
		let session = TestServerSession()
		session.config.connectionName = "Libera"
		session.userNickname = "Alice"
		session.away.isAway = true

		let content = MainWindowTitleContent(session: session, conversation: nil)

		#expect(content.subtitle.contains("Alice (away)"))
	}

	@Test("Disconnecting outranks connecting, logging on, and disconnected", arguments: 0 ..< 16)
	func disconnectingStatusTakesPrecedence(flags: Int) {
		let session = TestServerSession()
		session.isConnecting = flags & 1 != 0
		session.isConnected = flags & 2 != 0
		session.isLoggedIn = flags & 4 != 0
		session.isQuitting = flags & 8 == 0
		session.isDisconnecting = flags & 8 != 0

		let content = MainWindowTitleContent(session: session, conversation: nil)
		#expect(content.subtitle.hasPrefix(MainWindowConnectionStatus.disconnecting.title))
	}

	@Test("The native window updates a selected child's status when its session changes")
	func selectedChildReceivesSessionTitleUpdates() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let session = TestServerSession()
		session.config.connectionName = "Test Network"
		session.userNickname = "Alice"
		let channel = Conversation(config: ConversationConfig(name: "#swift"))
		channel.associatedSession = session
		window.selectedItem = channel
		window.updateTitle()

		let phases: [MainWindowConnectionStatus?] = [
			.disconnected, .connecting, .loggingOn, nil, .disconnecting, .disconnected,
		]
		for status in phases {
			session.isConnecting = status == .connecting
			session.isConnected = status == .loggingOn || status == nil || status == .disconnecting
			session.isLoggedIn = status == nil || status == .disconnecting
			session.isQuitting = status == .disconnecting
			window.updateTitle(for: session)

			#expect(window.selectedItem === channel)
			#expect(window.title == "#swift")
			let expectedSubtitle = [
				status?.title,
				"Test Network",
				MainWindowTitleContent.memberCount(0),
			].compactMap(\.self).joined(separator: " · ")
			#expect(window.subtitle == expectedSubtitle)
			#expect(window.accessibilityIdentifier() == "main-window")
			#expect(window.accessibilityTitle() == "#swift, " + expectedSubtitle)
		}
	}

	@Test("Unselected siblings and other networks do not update the native title")
	func unrelatedItemsDoNotUpdateTitle() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let session = TestServerSession()
		session.config.connectionName = "Test Network"
		let selected = Conversation(config: ConversationConfig(name: "#selected"))
		selected.associatedSession = session
		let sibling = Conversation(config: ConversationConfig(name: "#other"))
		sibling.associatedSession = session
		window.selectedItem = selected
		window.updateTitle()
		let subtitle = window.subtitle
		let accessibleTitle = window.accessibilityTitle()

		session.isConnecting = true
		window.updateTitle(for: sibling)
		window.updateTitle(for: TestServerSession())
		#expect(window.subtitle == subtitle)
		#expect(window.accessibilityTitle() == accessibleTitle)

		window.updateTitle(for: selected)
		#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.connecting.title))
	}

	@Test("A selected child's native title distinguishes waiting, cancelled, and retrying connections")
	func reconnectTitleTransitions() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let session = TestServerSession()
		let channel = Conversation(config: ConversationConfig(name: "#swift"))
		channel.associatedSession = session
		window.selectedItem = channel
		session.reconnect.timer.start(3600, repeats: false)
		defer { session.reconnect.timer.stop() }
		window.updateTitle(for: session)
		#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.waitingToReconnect.title))
		#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)

		session.cancelReconnect()
		window.updateTitle(for: session)
		#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.disconnected.title))
		session.isConnecting = true
		for mode in [SessionConnectMode.reconnect, .retry] {
			session.connectType = mode
			window.updateTitle(for: session)
			#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.reconnecting.title))
			#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)
		}
	}

	@Test("Server selection and clearing selection replace both native and accessible titles")
	func serverAndEmptySelectionReplaceAccessibleTitle() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let session = TestServerSession()
		session.config.connectionName = "Test Network"
		window.selectedItem = session
		window.updateTitle(for: session)
		#expect(window.title == "Test Network")
		#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)

		session.isDisconnecting = true
		window.updateTitle(for: session)
		#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.disconnecting.title))
		#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)

		window.selectedItem = nil
		window.updateTitle()
		#expect(window.title == ApplicationInfo.applicationName())
		#expect(window.subtitle.isEmpty)
		#expect(window.accessibilityTitle() == ApplicationInfo.applicationName())
		#expect(window.accessibilityIdentifier() == "main-window")
	}
}
