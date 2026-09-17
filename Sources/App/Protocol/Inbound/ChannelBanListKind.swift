// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Which list of masks a channel keeps a mask on.

 Bans, ban exceptions, invite exceptions and quiets are four lists with the
 same shape: a mask, who set it and when. They share the numerics that read
 them back and the window that shows them, so one kind names all four. */
enum ChannelBanListKind: Sendable {
	case ban
	case inviteException
	case banException
	case quiet

	/// The list numeric and the one that ends it name the same list, so both
	/// map to it: the mode letter a reply belongs to has to be answerable for
	/// the end of a list as well as for its entries.
	init(numeric: ServerNumeric) {
		switch numeric {
		case .banlist, .endofbanlist: self = .ban
		case .invitelist, .endofinvitelist: self = .inviteException
		case .exceptlist, .endofexceptlist: self = .banException
		default: self = .quiet
		}
	}

	/// The ISUPPORT list this kind is, which is what names its mode letter:
	/// `EXCEPTS` and `INVEX` may advertise a letter other than `e` and `I`.
	var supportListType: ISupportListType {
		switch self {
		case .ban: .ban
		case .banException: .banException
		case .inviteException: .inviteException
		case .quiet: .quiet
		}
	}

	/// One list entry as the console prints it. A server that answers without
	/// a setter and a date says only that the mask is on the list.
	func entryText(channelName: String, mask: String, setBy: String?, date: String?) -> String {
		if let setBy, let date {
			switch self {
			case .ban: String(localized: .IRC.banInSet(channelName, mask, setBy, date))
			case .inviteException: String(localized: .IRC.inviteExceptionInSet(channelName, mask, setBy, date))
			case .banException: String(localized: .IRC.banExceptionInSet(channelName, mask, setBy, date))
			case .quiet: String(localized: .IRC.quietInSet(channelName, mask, setBy, date))
			}
		} else {
			switch self {
			case .ban: String(localized: .IRC.banList(channelName, mask))
			case .inviteException: String(localized: .IRC.inviteException(channelName, mask))
			case .banException: String(localized: .IRC.banException(channelName, mask))
			case .quiet: String(localized: .IRC.quietList(channelName, mask))
			}
		}
	}
}
