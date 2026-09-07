/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
		let client = GLTTestClient()
		client.config.connectionName = "Libera"
		client.server = Server(serverAddress: "irc.example.test")
		client.userNickname = "Alice"

		let content = MainWindowTitleContent(client: client, channel: nil)

		#expect(content.title == "Libera")
		#expect(content.subtitle == [
			MainWindowStrings.ConnectionStatus.disconnected.title,
			"Alice",
			"irc.example.test",
		].joined(separator: " · "))
	}

	@Test("A channel selection adds the network, identity, and member count")
	func channelSelectionComposition() {
		let client = GLTTestClient()
		client.config.connectionName = "Libera"
		client.userNickname = "Alice"
		let channel = Channel(config: ChannelConfig(channelName: "#swift"))

		let content = MainWindowTitleContent(client: client, channel: channel)

		#expect(content.title == "#swift")
		#expect(content.subtitle == [
			MainWindowStrings.ConnectionStatus.disconnected.title,
			"Libera",
			"Alice",
			MainWindowStrings.Conversation.userCount(formattedNumber(0) as String),
		].joined(separator: " · "))
	}

	@Test("Disconnecting outranks connecting, logging on, and disconnected", arguments: 0 ..< 16)
	func disconnectingStatusTakesPrecedence(flags: Int) {
		let client = GLTTestClient()
		client.isConnecting = flags & 1 != 0
		client.isConnected = flags & 2 != 0
		client.isLoggedIn = flags & 4 != 0
		client.isQuitting = flags & 8 == 0
		client.isDisconnecting = flags & 8 != 0

		let content = MainWindowTitleContent(client: client, channel: nil)
		#expect(content.subtitle.hasPrefix(MainWindowStrings.ConnectionStatus.disconnecting.title))
	}

	@Test("The native window updates a selected child's status when its client changes")
	func selectedChildReceivesClientTitleUpdates() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let client = GLTTestClient()
		client.config.connectionName = "Test Network"
		client.userNickname = "Alice"
		let channel = Channel(config: ChannelConfig(channelName: "#swift"))
		channel.associatedClient = client
		window.selectedItem = channel
		window.updateTitle()

		let phases: [MainWindowStrings.ConnectionStatus?] = [
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
				"Alice",
				MainWindowStrings.Conversation.userCount(formattedNumber(0) as String),
			].compactMap(\.self).joined(separator: " · ")
			#expect(window.subtitle == expectedSubtitle)
			#expect(window.accessibilityIdentifier() == "main-window")
			#expect(window.accessibilityTitle() == "#swift, " + expectedSubtitle)
		}
	}

	@Test("Unselected siblings and other networks do not update the native title")
	func unrelatedItemsDoNotUpdateTitle() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let client = GLTTestClient()
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
		window.updateTitle(for: GLTTestClient())
		#expect(window.subtitle == subtitle)
		#expect(window.accessibilityTitle() == accessibleTitle)

		window.updateTitle(for: selected)
		#expect(window.subtitle.hasPrefix(MainWindowStrings.ConnectionStatus.connecting.title))
	}

	@Test("A selected child's native title distinguishes waiting, cancelled, and retrying connections")
	func reconnectTitleTransitions() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let client = GLTTestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#swift"))
		channel.associatedClient = client
		window.selectedItem = channel
		client.reconnectTimer.start(3600, repeats: false)
		defer { client.reconnectTimer.stop() }
		window.updateTitle(for: client)
		#expect(window.subtitle.hasPrefix(MainWindowStrings.ConnectionStatus.waitingToReconnect.title))
		#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)

		client.cancelReconnect()
		window.updateTitle(for: client)
		#expect(window.subtitle.hasPrefix(MainWindowStrings.ConnectionStatus.disconnected.title))
		client.isConnecting = true
		for mode in [IRCClientConnectMode.reconnect, .retry] {
			client.connectType = mode
			window.updateTitle(for: client)
			#expect(window.subtitle.hasPrefix(MainWindowStrings.ConnectionStatus.reconnecting.title))
			#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)
		}
	}

	@Test("Server selection and clearing selection replace both native and accessible titles")
	func serverAndEmptySelectionReplaceAccessibleTitle() {
		let window = MainWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
		let client = GLTTestClient()
		client.config.connectionName = "Test Network"
		window.selectedItem = client
		window.updateTitle(for: client)
		#expect(window.title == "Test Network")
		#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)

		client.isDisconnecting = true
		window.updateTitle(for: client)
		#expect(window.subtitle.hasPrefix(MainWindowStrings.ConnectionStatus.disconnecting.title))
		#expect(window.accessibilityTitle() == window.title + ", " + window.subtitle)

		window.selectedItem = nil
		window.updateTitle()
		#expect(window.title == ApplicationInfo.applicationName())
		#expect(window.subtitle.isEmpty)
		#expect(window.accessibilityTitle() == ApplicationInfo.applicationName())
		#expect(window.accessibilityIdentifier() == "main-window")
	}
}
