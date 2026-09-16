/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Localized dialog copy")
struct LocalizationCatalogBoundaryTests {
	@Test("The server channel list counts what it kept, in the singular too")
	func serverChannelListCopyAndFormatting() {
		#expect(String(localized: .ServerChannelList.publicChannelCount(1)) == "1 public channel")
		#expect(String(localized: .ServerChannelList.publicChannelCount(42)) == "42 public channels")
		/* The notice used to read "the first 1 are here" whatever the count. */
		#expect(String(localized: .ServerChannelList.listTruncatedNotice(1)).contains("the first one is here"))
		#expect(String(localized: .ServerChannelList.listTruncatedNotice(20)).contains("the first 20 are here"))
	}

	@Test("A channel access list names its own mode, and a maximum of zero states no limit")
	func channelBanListCopyAndFormatting() {
		#expect(ChannelBanListEntryType.ban.heading(channelName: "#swift") == "Bans in #swift")
		#expect(
			ChannelBanListEntryType.banException.heading(channelName: "#swift") == "Ban Exceptions in #swift"
		)
		#expect(
			ChannelBanListEntryType.inviteException.heading(channelName: "#swift")
				== "Invite Exceptions in #swift"
		)
		#expect(ChannelBanListEntryType.quiet.heading(channelName: "#swift") == "Quiets in #swift")
		#expect(ChannelBanListModel.entryCountDescription(4, maximum: 0, isTruncated: false) == "4 entries")
		#expect(ChannelBanListModel.entryCountDescription(4, maximum: 100, isTruncated: false) == "4 of 100 entries")
		/* A list cut at the window's cap must not read as a complete one that
		 happens to be exactly that long. */
		#expect(ChannelBanListModel.entryCountDescription(4, maximum: 100, isTruncated: true) == "First 4 entries")
		/* The notice under the list says why the count is not the whole of it;
		 repeating the count in it said the same thing twice. */
		#expect(
			String(localized: .ChannelBanList.listTruncatedNotice)
				== "The server sent more entries than this window keeps."
		)
	}

	/** The three counts above an access list used to mix the number format style's
	 grouped output with a raw `%ld`, so the same number was grouped in one of
	 them and printed bare in the others. */
	@Test("Every count above an access list formats its number the same way")
	func accessListCountsFormatOneNumberOneWay() {
		let formatted = 20000.formatted(.number)

		#expect(ChannelBanListModel.entryCountDescription(20000, maximum: 0, isTruncated: false).contains(formatted))
		#expect(ChannelBanListModel.entryCountDescription(20000, maximum: 50000, isTruncated: false).contains(formatted))
		#expect(ChannelBanListModel.entryCountDescription(20000, maximum: 50000, isTruncated: true).contains(formatted))
	}

	@Test("Channel spotlight pluralizes its unread and highlight counts")
	func channelSpotlightCopyAndFormatting() {
		#expect(String(localized: .ChannelSpotlight.channelOnNetwork("#swift", "Libera.Chat")) == "#swift on Libera.Chat")
		#expect(String(localized: .ChannelSpotlight.unreadMessageCount(1)) == "1 unread message")
		#expect(String(localized: .ChannelSpotlight.unreadMessageCount(2)) == "2 unread messages")
		#expect(String(localized: .ChannelSpotlight.highlightCount(1)) == "1 highlight")
		#expect(String(localized: .ChannelSpotlight.highlightCount(2)) == "2 highlights")
		#expect(
			String(localized: .ChannelSpotlight.joinsTwoChannelStatus(
				"1 highlight",
				"2 unread messages"
			)) == "1 highlight, 2 unread messages"
		)
	}
}
