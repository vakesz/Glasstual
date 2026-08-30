/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Localized dialog copy")
struct LocalizationCatalogBoundaryTests {
	@Test("The server channel list interpolates its network name and channel count")
	func serverChannelListCopyAndFormatting() {
		#expect(ServerChannelListStrings.heading(networkName: "Libera.Chat") == "Channel List for “Libera.Chat”")
		#expect(ServerChannelListStrings.windowTitle(publicChannelCount: 42) == "Channel List — 42 Public Channels")
	}

	@Test("A channel access list names its own mode, and a maximum of zero states no limit")
	func channelAccessListCopyAndFormatting() {
		#expect(ChannelAccessListStrings.heading(for: .ban, channelName: "#swift") == "Bans in #swift")
		#expect(
			ChannelAccessListStrings.heading(for: .banException, channelName: "#swift") == "Ban Exceptions in #swift"
		)
		#expect(
			ChannelAccessListStrings.heading(for: .inviteException, channelName: "#swift")
				== "Invite Exceptions in #swift"
		)
		#expect(ChannelAccessListStrings.heading(for: .quiet, channelName: "#swift") == "Quiets in #swift")
		#expect(ChannelAccessListStrings.entryCount(4, maximum: 0) == "4 entries")
		#expect(ChannelAccessListStrings.entryCount(4, maximum: 100) == "4 of 100 entries")
	}

	@Test("Channel spotlight pluralizes its unread and highlight counts")
	func channelSpotlightCopyAndFormatting() {
		#expect(ChannelSpotlightStrings.channelName("#swift") == "#swift")
		#expect(ChannelSpotlightStrings.networkSuffix("Libera.Chat") == " on Libera.Chat")
		#expect(ChannelSpotlightStrings.unreadMessages(1) == "1 unread message")
		#expect(ChannelSpotlightStrings.unreadMessages(2) == "2 unread messages")
		#expect(ChannelSpotlightStrings.highlights(1) == "1 highlight")
		#expect(ChannelSpotlightStrings.highlights(2) == "2 highlights")
		#expect(
			ChannelSpotlightStrings.combined("1 highlight", "2 unread messages") == "1 highlight, 2 unread messages"
		)
	}
}
