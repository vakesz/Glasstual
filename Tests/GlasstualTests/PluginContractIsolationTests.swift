/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Plugin contract isolation")
struct PluginContractIsolationTests {
	@Test("Plugin dispatch reaches a text handler on the main actor")
	func textDispatchRunsOnTheMainActor() {
		let handler = RecordingTextHandler()

		#expect(handler.receivedText(makeTextEvent()))
		#expect(handler.sawMainActor == true)
	}

	@Test("Plugin dispatch reaches a command handler on the main actor")
	func commandDispatchRunsOnTheMainActor() {
		let handler = RecordingCommandHandler()

		handler.userInputCommandInvoked(makeCommandInvocation())

		#expect(handler.sawMainActor == true)
	}

	@Test("A server message an interceptor edits leaves the original alone")
	func serverMessageHasValueSemantics() {
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

		var intercepted = original
		intercepted.command = "PRIVMSG"
		intercepted.parameters.append("world")
		intercepted.sender.nickname = "someone"

		#expect(original.command == "NOTICE")
		#expect(original.parameters == ["hello"])
		#expect(original.sender.nickname == "server")
		#expect(intercepted.command == "PRIVMSG")
		#expect(intercepted != original)
	}

	@Test("No rank is the empty set, not a bit of its own")
	func userRankNoneIsEmpty() {
		#expect(UserRank.none.rawValue == 0)
		#expect(UserRank.none.isEmpty)
		#expect(UserRank.none == UserRank([]))
	}

	@Test(
		"Inserting no rank leaves a set unchanged",
		arguments: [
			UserRank([]),
			UserRank([.voiced]),
			UserRank([.channelOwner, .normalOperator]),
		]
	)
	func insertingNoRankIsANoOperation(_ ranks: UserRank) {
		var result = ranks
		result.insert(.none)

		#expect(result == ranks)
		#expect(result.contains(.none))
	}

	@Test("A ranked user is never reported as unranked")
	func rankedUsersDoNotCarryNone() {
		let ranked: UserRank = [.halfOperator]

		#expect(ranked.rawValue != 0)
		#expect(ranked.subtracting(.none) == ranked)
	}
}

@MainActor
private final class RecordingTextHandler: PluginTextEventHandling {
	private(set) var sawMainActor = false

	func receivedText(_: PluginTextEvent) -> Bool {
		MainActor.preconditionIsolated()
		sawMainActor = true
		return true
	}
}

@MainActor
private final class RecordingCommandHandler: PluginCommandHandling {
	private(set) var sawMainActor = false

	var subscribedUserInputCommands: [String] {
		["record"]
	}

	func userInputCommandInvoked(_: PluginCommandInvocation) {
		MainActor.preconditionIsolated()
		sawMainActor = true
	}
}

@MainActor
private func makeTextEvent() -> PluginTextEvent {
	let channel = makeChannel()

	return PluginTextEvent(
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
		client: makeClient(channel: channel),
		receivedAt: Date(timeIntervalSince1970: 42),
		wasEncrypted: false
	)
}

@MainActor
private func makeCommandInvocation() -> PluginCommandInvocation {
	let channel = makeChannel()
	let client = makeClient(channel: channel)

	return PluginCommandInvocation(
		client: client,
		command: "RECORD",
		message: "",
		selectedChannel: channel,
		connectedClients: [client]
	)
}

@MainActor
private func makeChannel() -> PluginChannel {
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
private func makeClient(channel: PluginChannel) -> PluginClient {
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
