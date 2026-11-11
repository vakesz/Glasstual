// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A token the session reads out of an ISUPPORT line.

 The raw value is the token name as the server writes it, upper-cased. Only a
 token with a case here is read at all, and every one of them is cleared by
 `reset` — the reset switch is exhaustive, so a case added below is a token the
 session both reads and forgets.
 */
nonisolated enum ISupportToken: String, CaseIterable, Sendable {
	case accountextban = "ACCOUNTEXTBAN"
	/// `draft/account-registration`: the server only lets in users who are
	/// signed in to an account.
	case accountrequired = "ACCOUNTREQUIRED"
	case awaylen = "AWAYLEN"
	case bot = "BOT"
	case callerid = "CALLERID"
	case casemapping = "CASEMAPPING"
	case chanlimit = "CHANLIMIT"
	case chanmodes = "CHANMODES"
	case channellen = "CHANNELLEN"
	case chantypes = "CHANTYPES"
	case chathistory = "CHATHISTORY"
	case clienttagdeny = "CLIENTTAGDENY"
	case deaf = "DEAF"
	case elist = "ELIST"
	case excepts = "EXCEPTS"
	case extban = "EXTBAN"
	case icon = "ICON"
	case invex = "INVEX"
	case keylen = "KEYLEN"
	case kicklen = "KICKLEN"
	case linelen = "LINELEN"
	case maxlist = "MAXLIST"
	case maxtargets = "MAXTARGETS"
	case modes = "MODES"
	case monitor = "MONITOR"
	case msgreftypes = "MSGREFTYPES"
	case namesx = "NAMESX"
	case network = "NETWORK"
	case nicklen = "NICKLEN"
	case prefix = "PREFIX"
	case safelist = "SAFELIST"
	case silence = "SILENCE"
	case statusmsg = "STATUSMSG"
	case targmax = "TARGMAX"
	case topiclen = "TOPICLEN"
	case uhnames = "UHNAMES"
	case utf8only = "UTF8ONLY"
	case watch = "WATCH"
	case whox = "WHOX"

	/// Matches the token however the server capitalised it, and under the
	/// draft name a server may still advertise it by.
	init?(tokenName: String) {
		let normalized = tokenName.uppercased()

		if let token = Self.draftAliases[normalized] {
			self = token

			return
		}

		self.init(rawValue: normalized)
	}

	/** Whether an explicitly empty value means "the server has none of these".

	 modern.ircdocs.horse gives an empty value that meaning for the tokens whose
	 value is a list of characters. For every other token an empty value says no
	 more than the bare token does. */
	var readsAnEmptyValueAsNone: Bool {
		switch self {
		case .chantypes, .msgreftypes, .prefix, .statusmsg: true
		default: false
		}
	}

	/// The names a token goes by while its specification is a draft, which a
	/// server advertises in place of the bare name.
	private static let draftAliases: [String: ISupportToken] = [
		"DRAFT/ACCOUNTREQUIRED": .accountrequired,
		"DRAFT/CHATHISTORY": .chathistory,
		"DRAFT/ICON": .icon,
	]
}
