/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
@_spi(Host) import GlasstualPluginKit
import XCTest

@MainActor
final class PluginKitMigrationTests: XCTestCase {
	func testServerInputIsAPlainSwiftValueContainer() {
		let input = PluginServerInput()
		input.senderNickname = "alice"
		input.messageCommand = "PRIVMSG"
		input.messageParameters = ["#glasstual", "hello"]

		XCTAssertEqual(input.senderNickname, "alice")
		XCTAssertEqual(input.messageCommand, "PRIVMSG")
		XCTAssertEqual(input.messageParameters, ["#glasstual", "hello"])
	}

	func testHostContextExposesOnlyTypedPluginModels() {
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
			observeConnectionState: { handler in
				handler(true)
				return PluginObservation(cancellation: {})
			},
			removesFormatting: { true }
		)

		let observation = host.observeConnectionState { observedConnection = $0 }

		XCTAssertEqual(host.clients, [client])
		XCTAssertEqual(host.selectedChannel, channel)
		XCTAssertEqual(host.applicationMetrics, metrics)
		XCTAssertTrue(host.removesIRCFormatting)
		XCTAssertTrue(observedConnection)
		observation.cancel()
	}

	func testChannelSelectionUsesTypedPluginBoundary() {
		let selectionControllerType: any PluginChannelSelection.Type = ChannelSelectionViewController.self

		XCTAssertTrue(selectionControllerType == ChannelSelectionViewController.self)
	}

	func testNativeCommandContractCarriesTypedContext() {
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

		XCTAssertEqual(handler.client, client)
		XCTAssertEqual(handler.command, "BRAG")
		XCTAssertEqual(handler.message, "now")
		XCTAssertEqual(handler.selectedChannel, channel)
	}

	@MainActor
	func testNativeTextContractPreservesDomainValues() {
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

		XCTAssertTrue(handler.receivedText(event))
		XCTAssertEqual(handler.destination, channel)
		XCTAssertEqual(handler.kind, .privateMessage)
		XCTAssertEqual(handler.authorNickname, "alice")
	}

	func testServerMessageCopyCanBeInterceptedWithoutMutatingOriginal() {
		let original = PluginServerMessage(
			sender: PluginSender(
				nickname: "server",
				username: nil,
				address: nil,
				hostmask: "server",
				isServer: true
			),
			command: "NOTICE",
			parameters: ["hello"],
			isPrintOnlyMessage: false
		)
		let intercepted = original.copy()
		intercepted.command = "PRIVMSG"

		XCTAssertEqual(original.command, "NOTICE")
		XCTAssertEqual(intercepted.command, "PRIVMSG")
	}

	func testSwiftNativeCompatibilityFloorIsVersionEight() {
		XCTAssertEqual(PluginCompatibility.minimumHostVersion, "8.0.0")
	}

	func testHumanReadableTimeIntervalUsesNativeLocalizedComponents() {
		let startDate = Date()
		let endDate = startDate.addingTimeInterval(61)
		let expected = Date.ComponentsFormatStyle(
			style: .wide,
			calendar: .autoupdatingCurrent,
			fields: [.minute, .second]
		).format(startDate ..< endDate)

		XCTAssertEqual(
			PluginHost.humanReadableTimeInterval(61, shortValue: false, units: [.minute, .second]),
			expected
		)
	}

	func testFormattedNumberUsesTheCurrentLocale() {
		let value = 1_234_567

		XCTAssertEqual(
			PluginHost.formattedNumber(value),
			value.formatted(.number.locale(.autoupdatingCurrent))
		)
	}

	func testShortHumanReadableTimeIntervalUsesLargestNonzeroComponent() {
		let startDate = Date()
		let endDate = startDate.addingTimeInterval(3661)
		let expected = Date.ComponentsFormatStyle(
			style: .wide,
			calendar: .autoupdatingCurrent,
			fields: [.hour]
		).format(startDate ..< endDate)

		XCTAssertEqual(
			PluginHost.humanReadableTimeInterval(3661, shortValue: true),
			expected
		)
	}
}

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

private func makePluginChannel() -> PluginChannel {
	PluginChannel(
		hostObject: NSObject(),
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

private func makePluginClient(channel: PluginChannel) -> PluginClient {
	PluginClient(
		hostObject: NSObject(),
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
