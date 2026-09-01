/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
}
