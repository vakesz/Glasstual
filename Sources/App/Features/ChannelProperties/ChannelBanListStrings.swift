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

import Foundation

enum ChannelBanListStrings {
	static var hostmask: String {
		String(localized: .ChannelBanList.hostmask)
	}

	static var addedBy: String {
		String(localized: .ChannelBanList.addedBy)
	}

	static var created: String {
		String(localized: .ChannelBanList.created)
	}

	static var accessList: String {
		String(localized: .ChannelBanList.accessList)
	}

	static var removeSelected: String {
		String(localized: .ChannelBanList.removeSelected)
	}

	static var updateList: String {
		String(localized: .ChannelBanList.updateList)
	}

	static var loadingList: String {
		String(localized: .ChannelBanList.loadingList)
	}

	static var emptyTitle: String {
		String(localized: .ChannelBanList.emptyTitle)
	}

	static var emptyDescription: String {
		String(localized: .ChannelBanList.emptyDescription)
	}

	static func heading(for entryType: ChannelBanListEntryType, channelName: String) -> String {
		switch entryType {
		case .ban:
			String(localized: .ChannelBanList.headingForTheBanBans(channelName))
		case .banException:
			String(localized: .ChannelBanList.banExceptions(channelName))
		case .inviteException:
			String(localized: .ChannelBanList.inviteExceptions(channelName))
		case .quiet:
			String(localized: .ChannelBanList.headingForTheQuietQuiets(channelName))
		}
	}

	/// - Parameter isTruncated: Whether the window dropped entries the server
	///   sent. Neither the bare count nor the `MAXLIST` comparison may be used
	///   then: both read as the list being all of it.
	static func entryCount(_ count: Int, maximum: Int, isTruncated: Bool) -> String {
		if isTruncated {
			return String(localized: .ChannelBanList.entryCountTruncated(count))
		}

		guard maximum > 0 else {
			return String(localized: .ChannelBanList.entryCount(count))
		}

		return String(localized: .ChannelBanList.ofEntries(count, maximum))
	}

	/// Why the count above the list is not the whole list. Saying how many are
	/// shown as well would repeat the count itself.
	static var truncationNotice: String {
		String(localized: .ChannelBanList.listTruncatedNotice)
	}
}
