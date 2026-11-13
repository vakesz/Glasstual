// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

private nonisolated func focusState( // nonisolated: pure
	_ mode: FocusFilterState.Mode = .muteNotifications,
	networks: Set<String> = [],
	kind: FocusFilterState.ConversationKind = .all,
	exempt: Bool = false
) -> FocusFilterState {
	FocusFilterState(
		mode: mode,
		networkIdentifiers: networks,
		conversationKind: kind,
		exemptsHighlightsAndDirectMessages: exempt
	)
}

@Suite("Focus filter state")
struct FocusFilterStateTests {
	struct SuppressionCase: Sendable {
		let state: FocusFilterState
		let event: UserNotificationEvent
		let network: String
		let isDirect: Bool?
		let suppressed: Bool
	}

	@Test(
		"Mode and network scope decide whether the filter mutes",
		arguments: [
			SuppressionCase(state: focusState(), event: .channelMessage, network: "a", isDirect: false, suppressed: true),
			SuppressionCase(state: focusState(.setAway), event: .channelMessage, network: "a", isDirect: false, suppressed: false),
			SuppressionCase(state: focusState(.muteAndSetAway), event: .highlight, network: "a", isDirect: false, suppressed: true),
			SuppressionCase(state: focusState(networks: ["a"]), event: .highlight, network: "a", isDirect: false, suppressed: true),
			SuppressionCase(
				state: focusState(networks: ["a"]), event: .highlight, network: "b", isDirect: false, suppressed: false
			),
			SuppressionCase(
				state: focusState(networks: ["a", "b"]), event: .highlight, network: "b", isDirect: nil, suppressed: true
			),
		]
	)
	func modeAndScope(_ testCase: SuppressionCase) {
		#expect(suppresses(testCase) == testCase.suppressed)
	}

	@Test(
		"The conversation kind narrows what is muted",
		arguments: [
			SuppressionCase(state: focusState(kind: .channels), event: .channelMessage, network: "a", isDirect: false, suppressed: true),
			SuppressionCase(state: focusState(kind: .channels), event: .privateMessage, network: "a", isDirect: true, suppressed: false),
			SuppressionCase(state: focusState(kind: .channels), event: .userJoined, network: "a", isDirect: nil, suppressed: false),
			SuppressionCase(
				state: focusState(kind: .directMessages), event: .privateMessage, network: "a", isDirect: true, suppressed: true
			),
			SuppressionCase(
				state: focusState(kind: .directMessages), event: .channelMessage, network: "a", isDirect: false, suppressed: false
			),
			SuppressionCase(state: focusState(kind: .directMessages), event: .userJoined, network: "a", isDirect: nil, suppressed: false),
			SuppressionCase(state: focusState(kind: .all), event: .userJoined, network: "a", isDirect: nil, suppressed: true),
		]
	)
	func conversationKind(_ testCase: SuppressionCase) {
		#expect(suppresses(testCase) == testCase.suppressed)
	}

	@Test(
		"Highlights and direct messages can be exempted",
		arguments: [
			SuppressionCase(state: focusState(exempt: true), event: .highlight, network: "a", isDirect: false, suppressed: false),
			SuppressionCase(state: focusState(exempt: true), event: .newPrivateMessage, network: "a", isDirect: true, suppressed: false),
			SuppressionCase(state: focusState(exempt: true), event: .privateMessage, network: "a", isDirect: true, suppressed: false),
			SuppressionCase(state: focusState(exempt: true), event: .channelMessage, network: "a", isDirect: true, suppressed: false),
			SuppressionCase(state: focusState(exempt: true), event: .channelMessage, network: "a", isDirect: false, suppressed: true),
			SuppressionCase(state: focusState(exempt: true), event: .userJoined, network: "a", isDirect: nil, suppressed: true),
			SuppressionCase(state: focusState(exempt: false), event: .highlight, network: "a", isDirect: false, suppressed: true),
		]
	)
	func exemptions(_ testCase: SuppressionCase) {
		#expect(suppresses(testCase) == testCase.suppressed)
	}

	@Test("A file transfer question is never silenced")
	func fileTransfersAreNeverSilenced() {
		let filter = focusState()
		#expect(filter.suppresses(event: .fileTransferReceiveRequested, network: "a", isDirect: nil) == false)
	}

	@Test("Only the modes that set away set it, and only on the networks they reach")
	func awayScope() {
		#expect(focusState(.muteNotifications).setsAway(onNetwork: "a") == false)
		#expect(focusState(.setAway).setsAway(onNetwork: "a"))
		#expect(focusState(.muteAndSetAway, networks: ["a"]).setsAway(onNetwork: "a"))
		#expect(focusState(.muteAndSetAway, networks: ["a"]).setsAway(onNetwork: "b") == false)
	}

	@Test("The policy refuses a suppressed event but not a transfer")
	func policyHonorsSuppression() {
		func admits(_ event: UserNotificationEvent, suppressed: Bool) -> Bool {
			UserNotificationPolicy.admits(UserNotificationAdmissionContext(
				event: event,
				isTerminating: false,
				isCollapsingNetsplit: false,
				nicknameIsLocalUser: false,
				conversationIsMuted: false,
				focusSuppresses: suppressed
			))
		}

		#expect(admits(.highlight, suppressed: true) == false)
		#expect(admits(.highlight, suppressed: false))
		#expect(admits(.fileTransferReceiveRequested, suppressed: true))
	}

	@Test("The state survives a property-list round trip")
	func codableRoundTrip() throws {
		var original = focusState(.muteAndSetAway, networks: ["a", "b"], kind: .directMessages, exempt: true)
		original.awayMessage = "heads down"
		let data = try PropertyListEncoder().encode(original)
		#expect(try PropertyListDecoder().decode(FocusFilterState.self, from: data) == original)
	}

	private func suppresses(_ testCase: SuppressionCase) -> Bool {
		testCase.state.suppresses(event: testCase.event, network: testCase.network, isDirect: testCase.isDirect)
	}
}
