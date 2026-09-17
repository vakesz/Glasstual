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
		let content = MainWindowTitleContent(client: nil, channel: nil)

		#expect(content.title == ApplicationInfo.applicationName())
		#expect(content.subtitle.isEmpty)
	}

	@Test("A server selection composes status, nickname, and address in order")
	func serverSelectionComposition() {
		let client = TestClient()
		client.config.connectionName = "Libera"
		client.server = Server(serverAddress: "irc.example.test")
		client.userNickname = "Alice"

		let content = MainWindowTitleContent(client: client, channel: nil)

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
		let client = TestClient()
		client.config.connectionName = "Libera"
		client.userNickname = "Alice"
		let channel = Channel(config: ChannelConfig(channelName: "#swift"))

		let content = MainWindowTitleContent(client: client, channel: channel)

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
		let client = TestClient()
		client.config.connectionName = "Libera"
		client.userNickname = "Alice"
		client.userIsAway = true

		let content = MainWindowTitleContent(client: client, channel: nil)

		#expect(content.subtitle.contains("Alice (away)"))
	}

	@Test("Disconnecting outranks connecting, logging on, and disconnected", arguments: 0 ..< 16)
	func disconnectingStatusTakesPrecedence(flags: Int) {
		let client = TestClient()
		client.isConnecting = flags & 1 != 0
		client.isConnected = flags & 2 != 0
		client.isLoggedIn = flags & 4 != 0
		client.isQuitting = flags & 8 == 0
		client.isDisconnecting = flags & 8 != 0

		let content = MainWindowTitleContent(client: client, channel: nil)
		#expect(content.subtitle.hasPrefix(MainWindowConnectionStatus.disconnecting.title))
	}

	@Test("The native window updates a selected child's status when its client changes")
	func selectedChildReceivesClientTitleUpdates() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let client = TestClient()
		client.config.connectionName = "Test Network"
		client.userNickname = "Alice"
		let channel = Channel(config: ChannelConfig(channelName: "#swift"))
		channel.associatedClient = client
		window.selectedItem = channel
		window.updateTitle()

		let phases: [MainWindowConnectionStatus?] = [
			.disconnected, .connecting, .loggingOn, nil, .disconnecting, .disconnected,
		]
		for status in phases {
			client.isConnecting = status == .connecting
			client.isConnected = status == .loggingOn || status == nil || status == .disconnecting
			client.isLoggedIn = status == nil || status == .disconnecting
			client.isQuitting = status == .disconnecting
			window.updateTitle(for: client)

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
		let client = TestClient()
		client.config.connectionName = "Test Network"
		let selected = Channel(config: ChannelConfig(channelName: "#selected"))
		selected.associatedClient = client
		let sibling = Channel(config: ChannelConfig(channelName: "#other"))
		sibling.associatedClient = client
		window.selectedItem = selected
		window.updateTitle()
		let subtitle = window.subtitle
		let accessibleTitle = window.accessibilityTitle()

		client.isConnecting = true
		window.updateTitle(for: sibling)
		window.updateTitle(for: TestClient())
		#expect(window.subtitle == subtitle)
		#expect(window.accessibilityTitle() == accessibleTitle)

		window.updateTitle(for: selected)
		#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.connecting.title))
	}

	@Test("A selected child's native title distinguishes waiting, cancelled, and retrying connections")
	func reconnectTitleTransitions() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let client = TestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#swift"))
		channel.associatedClient = client
		window.selectedItem = channel
		client.reconnect.timer.start(3600, repeats: false)
		defer { client.reconnect.timer.stop() }
		window.updateTitle(for: client)
		#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.waitingToReconnect.title))
		#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)

		client.cancelReconnect()
		window.updateTitle(for: client)
		#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.disconnected.title))
		client.isConnecting = true
		for mode in [ClientConnectMode.reconnect, .retry] {
			client.connectType = mode
			window.updateTitle(for: client)
			#expect(window.subtitle.hasPrefix(MainWindowConnectionStatus.reconnecting.title))
			#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)
		}
	}

	@Test("Server selection and clearing selection replace both native and accessible titles")
	func serverAndEmptySelectionReplaceAccessibleTitle() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let client = TestClient()
		client.config.connectionName = "Test Network"
		window.selectedItem = client
		window.updateTitle(for: client)
		#expect(window.title == "Test Network")
		#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)

		client.isDisconnecting = true
		window.updateTitle(for: client)
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
