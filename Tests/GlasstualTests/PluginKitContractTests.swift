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
struct PluginKitContractTests {
	/** `creationTime` is recorded in the 1970 epoch. Subtracting it from the
	 2001 epoch instead reads as a membership age of about -978,307,200 seconds
	 for every member, which no age comparison ever notices; `membershipAge` is
	 what keeps the epoch in one place. */
	@Test("Membership age is measured in the epoch the host records the join in")
	func membershipAgeUsesTheHostsEpoch() {
		let joined = Date().timeIntervalSince1970 - 90
		let member = PluginChannelMember(
			user: PluginUser(nickname: "alice", hostmask: nil, address: nil, isIRCop: false),
			mark: "",
			ranks: [],
			creationTime: joined
		)

		#expect(member.membershipAge >= 90)
		#expect(member.membershipAge < 120)
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

	/// A bundle declaring an older minimum is refused, so the floor is part of
	/// the contract a third-party plugin is built against.
	@Test("The compatibility floor for a plugin bundle is version eight")
	func swiftNativeCompatibilityFloorIsVersionEight() {
		#expect(PluginCompatibility.minimumHostVersion == "8.0.0")
	}

	/** The spelled-out form is what a WHOIS idle time and a timed command's
	 countdown are rendered with, so the decisions worth stating are the ones
	 the function makes on top of `Date.ComponentsFormatStyle`: which units it
	 selects, and that the wording is the platform's rather than the app's.

	 Restating the format call itself would only assert that the body is its own
	 body, so each case here is checked against another output of the same
	 function instead of against a second copy of the formatting. */
	@Test("Only the units the caller asked for are spelled out")
	func humanReadableTimeIntervalHonoursTheRequestedUnits() {
		let minutesAndSeconds = PluginHost.humanReadableTimeInterval(
			61,
			shortValue: false,
			units: [.minute, .second]
		)
		let secondsOnly = PluginHost.humanReadableTimeInterval(61, shortValue: false, units: [.second])

		#expect(minutesAndSeconds.isEmpty == false)
		#expect(secondsOnly.isEmpty == false)

		/* One minute and one second in two components, sixty-one in one. */
		#expect(minutesAndSeconds != secondsOnly)
		#expect(
			minutesAndSeconds
				== PluginHost.humanReadableTimeInterval(61, shortValue: false, units: [.minute, .second])
		)
	}

	/// An empty unit matrix is the caller saying "whatever fits", which the
	/// `orderMatrix` overload spells `0`.
	@Test("No unit matrix means every unit from years down to seconds")
	func humanReadableTimeIntervalDefaultsToEveryUnit() {
		let day = TimeInterval(90061)

		#expect(
			PluginHost.humanReadableTimeInterval(day, shortValue: false)
				== PluginHost.humanReadableTimeInterval(
					day,
					shortValue: false,
					units: [.year, .month, .day, .hour, .minute, .second]
				)
		)
		#expect(
			PluginHost.humanReadableTimeInterval(day, shortValue: false)
				!= PluginHost.humanReadableTimeInterval(day, shortValue: false, units: [.day])
		)
	}

	/// The interval is a distance, and a negative one is what an idle time
	/// computed against a server clock that is ahead produces.
	@Test("A negative interval reads the same as the distance it covers")
	func humanReadableTimeIntervalIgnoresDirection() {
		#expect(
			PluginHost.humanReadableTimeInterval(-3661, shortValue: false)
				== PluginHost.humanReadableTimeInterval(3661, shortValue: false)
		)
	}

	@Test("A short interval is spelled with its largest non-zero component alone")
	func shortHumanReadableTimeIntervalUsesLargestNonzeroComponent() {
		let short = PluginHost.humanReadableTimeInterval(3661, shortValue: true)

		/* An hour and a minute and a second collapses onto the hour, so it reads
		 exactly as a round hour does and differs from the full spelling. */
		#expect(short == PluginHost.humanReadableTimeInterval(3600, shortValue: true))
		#expect(short != PluginHost.humanReadableTimeInterval(3661, shortValue: false))
		#expect(
			PluginHost.humanReadableTimeInterval(61, shortValue: true)
				== PluginHost.humanReadableTimeInterval(60, shortValue: true)
		)
	}

	/// The point of routing plugin-facing counts through the host is that they
	/// carry the reader's own digit grouping instead of `String(describing:)`.
	@Test("A formatted number carries the current locale's grouping")
	func formattedNumberGroupsDigitsForTheCurrentLocale() {
		let formatted = PluginHost.formattedNumber(1_234_567)
		let separator = Locale.autoupdatingCurrent.groupingSeparator ?? ""

		#expect(formatted != "1234567")
		#expect(formatted.count > 7)

		if separator.isEmpty == false {
			#expect(formatted.contains(separator))
			#expect(formatted.replacingOccurrences(of: separator, with: "").count == 7)
		}

		#expect(PluginHost.formattedNumber(0).isEmpty == false)
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
