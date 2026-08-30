/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

@testable import Glasstual
import GlasstualPluginKit
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

	@Test("A private message is not drawn in the channel list")
	func privateMessagesAreNotDrawn() {
		let channels = [
			makeChannel(named: "#one", type: .channel),
			makeChannel(named: "someone", type: .privateMessage),
			makeChannel(named: "#two", type: .channel),
		]

		let displayed = ServerPropertiesSheet.displayedChannels(in: channels)

		#expect(displayed.map(\.channelName) == ["#one", "#two"])
	}

	@Test("A list of only channels is drawn whole")
	func channelsAreAllDrawn() {
		let channels = [
			makeChannel(named: "#one", type: .channel),
			makeChannel(named: "#two", type: .channel),
		]

		#expect(ServerPropertiesSheet.displayedChannels(in: channels).count == 2)
	}

	@Test("An empty list draws nothing rather than failing")
	func emptyListIsEmpty() {
		#expect(ServerPropertiesSheet.displayedChannels(in: []).isEmpty)
	}

	@Test("The rows keep the order the list is stored in")
	func orderIsPreserved() {
		let channels = [
			makeChannel(named: "#c", type: .channel),
			makeChannel(named: "someone", type: .privateMessage),
			makeChannel(named: "#a", type: .channel),
			makeChannel(named: "#b", type: .channel),
		]

		let displayed = ServerPropertiesSheet.displayedChannels(in: channels)

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
