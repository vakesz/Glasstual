// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/// The channel-list table shows regular channels only. That used to be an
/// `NSPredicate(format: "type == 0")` on an `NSArrayController`, which raised
/// `NSUnknownKeyException` the moment the list held anything: the configs are
/// Swift structs, the controller boxes them, and a box is not key-value coding
/// compliant. The rule is a Swift filter now, so it can be stated and checked.
@MainActor
@Suite("Server properties channel list")
struct ServerPropertiesSheetTableTests {
	private func makeChannel(named name: String, type: ChannelType) -> ChannelConfig {
		var config = ChannelConfig(channelName: name)
		config.type = type

		return config
	}

	private func displayedChannels(in channelList: [ChannelConfig]) -> [ChannelConfig] {
		var config = ClientConfig()
		config.channelList = channelList

		return ServerPropertiesModel(config: config).displayedChannels
	}

	@Test("A private message is not drawn in the channel list")
	func privateMessagesAreNotDrawn() {
		let channels = [
			makeChannel(named: "#one", type: .channel),
			makeChannel(named: "someone", type: .privateMessage),
			makeChannel(named: "#two", type: .channel),
		]

		let displayed = displayedChannels(in: channels)

		#expect(displayed.map(\.channelName) == ["#one", "#two"])
	}

	@Test("The rows keep the order the list is stored in")
	func orderIsPreserved() {
		let channels = [
			makeChannel(named: "#c", type: .channel),
			makeChannel(named: "someone", type: .privateMessage),
			makeChannel(named: "#a", type: .channel),
			makeChannel(named: "#b", type: .channel),
		]

		let displayed = displayedChannels(in: channels)

		#expect(displayed.map(\.channelName) == ["#c", "#a", "#b"])
	}

	/// The diff keys rows on `uniqueIdentifier`, and a snapshot holding the same
	/// identifier twice traps.
	@Test("Every channel carries an identity of its own")
	func identifiersAreDistinct() {
		let channels = (0 ..< 8).map { makeChannel(named: "#c\($0)", type: .channel) }
		let identifiers = Set(channels.map(\.uniqueIdentifier))

		#expect(identifiers.count == channels.count)
	}
}
