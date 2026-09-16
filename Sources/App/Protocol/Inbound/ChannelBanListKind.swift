/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

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
