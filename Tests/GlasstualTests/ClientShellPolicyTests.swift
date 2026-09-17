// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Client shell policies")
struct ClientShellPolicyTests {
	@Test("Channels are stored ahead of queries")
	func channelStoragePlacesChannelsBeforeQueries() {
		let client = TestClient()

		client.add(Channel(config: ChannelConfig(channelName: "#first")))
		client.add(Channel(config: ChannelConfig(channelName: "someone", type: .privateMessage)))
		client.add(Channel(config: ChannelConfig(channelName: "#second")))
		client.add(Channel(config: ChannelConfig(channelName: "other", type: .privateMessage)))

		#expect(client.channelList.map(\.name) == ["#first", "#second", "someone", "other"])
	}

	@Test("A utility window or a direct chat is never written to the stored configuration")
	func storedConfigurationExcludesTransientChannels() {
		#expect(
			ClientConfigurationPolicy.shouldStoreChannel(
				isUtility: true,
				isDirectChat: false,
				isChannel: true,
				rememberQueries: true
			) == false
		)
		#expect(
			ClientConfigurationPolicy.shouldStoreChannel(
				isUtility: false,
				isDirectChat: true,
				isChannel: false,
				rememberQueries: true
			) == false
		)
	}

	@Test("A query is stored only while the remember-queries preference is on")
	func storedConfigurationHonorsQueryPreference() {
		#expect(
			ClientConfigurationPolicy.shouldStoreChannel(
				isUtility: false,
				isDirectChat: false,
				isChannel: false,
				rememberQueries: false
			) == false
		)
		#expect(
			ClientConfigurationPolicy.shouldStoreChannel(
				isUtility: false,
				isDirectChat: false,
				isChannel: false,
				rememberQueries: true
			)
		)
	}
}
