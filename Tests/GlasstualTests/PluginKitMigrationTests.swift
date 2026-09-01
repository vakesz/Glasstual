/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Plugin Kit contracts")
struct PluginKitMigrationTests {
	@Test("Server input is a plain container the host fills in")
	func serverInputIsAPlainSwiftValueContainer() {
		var input = PluginServerInput()
		input.senderNickname = "alice"
		input.messageCommand = "PRIVMSG"
		input.messageParameters = ["#glasstual", "hello"]

		#expect(input.senderNickname == "alice")
		#expect(input.messageCommand == "PRIVMSG")
		#expect(input.messageParameters == ["#glasstual", "hello"])
	}

	@Test("Server input is a value: a handler's edits do not reach the next handler")
	func serverInputCopiesRatherThanShares() {
		var input = PluginServerInput()
		input.senderNickname = "alice"

		var handed = input
		handed.senderNickname = "mallory"

		#expect(input.senderNickname == "alice")
	}

	@Test("A posted message is a value the host finishes on the main actor")
	func postedMessageCarriesTypedSendableParts() {
		var message = PluginPostedMessage()
		message.lineNumber = "1234"
		message.messageContents = "see https://example.com"
		message.hyperlinks = [
			PluginHyperlink(
				uniqueIdentifier: "link-1",
				stringValue: "https://example.com",
				range: NSRange(location: 4, length: 19),
				strictMatch: true
			),
		]
		message.users = [
			PluginChannelMember(
				user: PluginUser(nickname: "alice", hostmask: nil, address: nil, isIRCop: false),
				mark: "@",
				ranks: [.normalOperator],
				creationTime: 0
			),
		]

		var copied = message
		copied.isProcessedInBulk = true

		#expect(message.isProcessedInBulk == false)
		#expect(copied.hyperlinks.first?.stringValue == "https://example.com")
		#expect(copied.users.first?.user.nickname == "alice")
	}

	@Test("The host context hands a plugin typed models and a cancellable observation")
	func hostContextExposesOnlyTypedPluginModels() {
		let channel = makePluginChannel()
		let client = makePluginClient(channel: channel)
		let metrics = PluginApplicationMetrics(
			messagesSent: 12,
			messagesReceived: 34,
			bandwidthIn: 56,
			bandwidthOut: 78,
			lastMessageReceived: 90,
			visibleLineCount: 123,
			usesDarkSidebar: true
		)
		var observedConnection = false
		let host = PluginHostContext(
			defaults: .standard,
			clients: { [client] },
			selectedChannel: { channel },
			metrics: { metrics },
			applicationSnapshot: { nil },
			themeSnapshot: { nil },
			observeConnectionState: { handler in
				handler(true)
				return PluginObservation(cancellation: {})
			},
			removesFormatting: { true }
		)

		let observation = host.observeConnectionState { observedConnection = $0 }

		#expect(host.clients == [client])
		#expect(host.selectedChannel == channel)
		#expect(host.applicationMetrics == metrics)
		#expect(host.removesIRCFormatting)
		#expect(observedConnection)
		observation.cancel()
	}

	@Test("A command invocation carries the client, text and selected channel to its handler")
	func nativeCommandContractCarriesTypedContext() {
		let channel = makePluginChannel()
		let client = makePluginClient(channel: channel)
		let invocation = PluginCommandInvocation(
			client: client,
			command: "BRAG",
			message: "now",
			selectedChannel: channel,
			connectedClients: [client]
		)
		let handler = CommandHandlerFixture()

		handler.userInputCommandInvoked(invocation)

		#expect(handler.client == client)
		#expect(handler.command == "BRAG")
		#expect(handler.message == "now")
		#expect(handler.selectedChannel == channel)
	}

	@Test("A text event carries its destination, kind and author to its handler")
	func nativeTextContractPreservesDomainValues() {
		let channel = makePluginChannel()
		let client = makePluginClient(channel: channel)
		let handler = TextHandlerFixture()
		let event = PluginTextEvent(
			text: "hello",
			author: PluginSender(
				nickname: "alice",
				username: "user",
				address: "example.test",
				hostmask: "alice!user@example.test",
				isServer: false
			),
			destination: channel,
			kind: .privateMessage,
			client: client,
			receivedAt: Date(timeIntervalSince1970: 42),
			wasEncrypted: true
		)

		#expect(handler.receivedText(event))
		#expect(handler.destination == channel)
		#expect(handler.kind == .privateMessage)
		#expect(handler.authorNickname == "alice")
	}

	/// A bundle declaring an older minimum is refused, so the floor is part of
	/// the contract a third-party plugin is built against.
	@Test("The compatibility floor for a plugin bundle is version eight")
	func swiftNativeCompatibilityFloorIsVersionEight() {
		#expect(PluginCompatibility.minimumHostVersion == "8.0.0")
	}

	@Test("A spelled-out interval matches the platform's own components format")
	func humanReadableTimeIntervalUsesNativeLocalizedComponents() {
		let startDate = Date()
		let endDate = startDate.addingTimeInterval(61)
		let expected = Date.ComponentsFormatStyle(
			style: .wide,
			calendar: .autoupdatingCurrent,
			fields: [.minute, .second]
		).format(startDate ..< endDate)

		#expect(PluginHost.humanReadableTimeInterval(61, shortValue: false, units: [.minute, .second]) == expected)
	}

	@Test("A formatted number follows the current locale")
	func formattedNumberUsesTheCurrentLocale() {
		let value = 1_234_567

		#expect(PluginHost.formattedNumber(value) == value.formatted(.number.locale(.autoupdatingCurrent)))
	}

	@Test("A short interval is spelled with its largest non-zero component alone")
	func shortHumanReadableTimeIntervalUsesLargestNonzeroComponent() {
		let startDate = Date()
		let endDate = startDate.addingTimeInterval(3661)
		let expected = Date.ComponentsFormatStyle(
			style: .wide,
			calendar: .autoupdatingCurrent,
			fields: [.hour]
		).format(startDate ..< endDate)

		#expect(PluginHost.humanReadableTimeInterval(3661, shortValue: true) == expected)
	}
}

@MainActor
private final class CommandHandlerFixture: PluginCommandHandling {
	private(set) var client: PluginClient?
	private(set) var command: String?
	private(set) var message: String?
	private(set) var selectedChannel: PluginChannel?

	var subscribedUserInputCommands: [String] {
		["brag"]
	}

	func userInputCommandInvoked(_ invocation: PluginCommandInvocation) {
		client = invocation.client
		command = invocation.command
		message = invocation.message
		selectedChannel = invocation.selectedChannel
	}
}

@MainActor
private final class TextHandlerFixture: PluginTextEventHandling {
	private(set) var destination: PluginChannel?
	private(set) var kind: PluginMessageKind?
	private(set) var authorNickname: String?

	func receivedText(_ event: PluginTextEvent) -> Bool {
		destination = event.destination
		kind = event.kind
		authorNickname = event.author.nickname
		return true
	}
}

@MainActor
private func makePluginChannel() -> PluginChannel {
	PluginChannel(
		identifier: "channel-id",
		name: "#glasstual",
		type: .channel,
		isActive: true,
		members: [],
		autoJoin: { true },
		setAutoJoin: { _ in },
		deactivate: {}
	)
}

@MainActor
private func makePluginClient(channel: PluginChannel) -> PluginClient {
	PluginClient(
		identifier: "client-id",
		userNickname: "tester",
		networkName: "Test Network",
		serverAddress: "irc.example.test",
		isConnected: true,
		isLoggedIn: true,
		isIRCop: false,
		localUser: nil,
		channels: [channel],
		isConnectedToZNC: false,
		zncCertificateChainData: nil,
		maximumNicknameLength: 50,
		nicknameMatchesZNCUser: { _, _ in false },
		isChannelName: { $0.hasPrefix("#") },
		findChannel: { $0 == channel.name ? channel : nil },
		privateMessage: { _ in nil },
		utilityChannel: { _ in nil },
		isCapabilityEnabled: { _ in false },
		printDebug: { _, _ in },
		sendPrivateMessage: { _, _ in },
		sendCommand: { _ in },
		sendLine: { _ in },
		joinChannel: { _ in },
		printMessage: { _, _, _, _, _, _, _, completion in
			completion(PluginPrintResult(isHighlight: false))
		},
		markUnread: { _, _ in },
		markHighlight: { _ in },
		refreshSidebar: {}
	)
}
