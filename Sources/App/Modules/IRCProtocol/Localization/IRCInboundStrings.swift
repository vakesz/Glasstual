/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

enum IRCInboundStrings {
	enum StandardReply {
		static func failure(command: String, code: String, description: String) -> String {
			String(localized: .IRC.p4R6N(command, code, description))
		}

		static func warning(command: String, code: String, description: String) -> String {
			String(localized: .IRC.y7TZk(command, code, description))
		}

		static func note(command: String, code: String, description: String) -> String {
			String(localized: .IRC.k2ECb(command, code, description))
		}
	}

	enum ChannelEvent {
		static func modeChanged(sender: String, mode: String) -> String {
			String(localized: .IRC.v5DIx(sender, mode))
		}

		static func topicChanged(sender: String, topic: String) -> String {
			String(localized: .IRC.qq266(sender, topic))
		}

		static func invitation(sender: String, invitee: String, channelName: String) -> String {
			String(localized: .IRC.invNt(sender, invitee, channelName))
		}

		static func invitation(
			sender: String,
			username: String,
			address: String,
			channelName: String
		) -> String {
			String(localized: .IRC.qw4T3(sender, username, address, channelName))
		}

		static func mode(_ mode: String) -> String {
			String(localized: .IRC.obpWw(mode))
		}

		static func topic(_ topic: String) -> String {
			String(localized: .IRC._7Nm7V(topic))
		}

		static func topicSet(by nickname: String, date: String) -> String {
			String(localized: .IRC.y7S3E(nickname, date))
		}

		static func inviting(_ nickname: String, to channelName: String) -> String {
			String(localized: .IRC.wk4Rv(nickname, channelName))
		}
	}

	enum Membership {
		static func joinedQuery(nickname: String) -> String {
			String(localized: .IRC.q0QCh(nickname))
		}

		static func joinedChannel(nickname: String, username: String, address: String) -> String {
			String(localized: .IRC.ziuP9(nickname, username, address))
		}

		static func partedChannel(nickname: String, username: String, address: String) -> String {
			String(localized: .IRC.nkrKf(nickname, username, address))
		}

		static func eventWithReason(_ event: String, reason: String) -> String {
			String(localized: .IRC.ozy6I(event, reason))
		}

		static var rejoinScheduled: String {
			String(localized: .IRC.zzj2H)
		}

		static func kicked(sender: String, target: String, reason: String) -> String {
			String(localized: .IRC._9AjBd(sender, target, reason))
		}

		static func quit(nickname: String, username: String, address: String) -> String {
			String(localized: .IRC._53BDm(nickname, username, address))
		}

		static func eventWithComment(_ event: String, comment: String) -> String {
			String(localized: .IRC.tokSt(event, comment))
		}

		static func leftQuery(nickname: String) -> String {
			String(localized: .IRC._8BkMx(nickname))
		}

		static func localNicknameChanged(to nickname: String) -> String {
			String(localized: .IRC.rr6Yo(nickname))
		}

		static func nicknameChanged(from oldNickname: String, to newNickname: String) -> String {
			String(localized: .IRC.fxw5S(oldNickname, newNickname))
		}
	}
}

extension IRCInboundStrings {
	enum Numeric {
		static var endOfSilenceList: String {
			String(localized: .IRC.m2VSc)
		}

		static var utf8EncodingRequired: String {
			String(localized: .IRC.y3HUd)
		}

		static func supportUpdate(previous: String, explanation: String) -> String {
			String(localized: .IRC.u51Nn(previous, explanation))
		}

		static func userModes(nickname: String, modes: String) -> String {
			String(localized: .IRC.ipj34(nickname, modes))
		}

		static func away(nickname: String, message: String) -> String {
			String(localized: .IRC.c1HFq(nickname, message))
		}

		static func silenceEntry(_ entry: String) -> String {
			String(localized: .IRC.m2VSb(entry))
		}

		static func operatorStatus(networkName: String) -> String {
			String(localized: .IRC._6BhBr(networkName))
		}

		static func website(_ website: String) -> String {
			String(localized: .IRC._8TqG6(website))
		}

		static func cannotMessageUnrecognizedUser(_ nickname: String) -> String {
			String(localized: .IRC._11IEv(nickname))
		}

		static func privateMessageBlocked(nickname: String, account: String) -> String {
			String(localized: .IRC._3YjIn(nickname, account))
		}

		static func nicknameUnavailable(_ nickname: String) -> String {
			String(localized: .IRC.js39V(nickname))
		}
	}

	enum Whois {
		static func connection(
			nickname: String,
			address: String,
			realName: String,
			isHistorical: Bool
		) -> String {
			if isHistorical {
				return String(localized: .IRC.x69Rz(nickname, address, realName))
			}

			return String(localized: .IRC._3OaMv(nickname, address, realName))
		}

		static func channels(nickname: String, channels: String) -> String {
			String(localized: .IRC.onkL5(nickname, channels))
		}

		static func bot(nickname: String) -> String {
			String(localized: .IRC.m2VSe(nickname))
		}

		static func connectedAt(nickname: String, server: String, date: String) -> String {
			String(localized: .IRC.cduEd(nickname, server, date))
		}

		static func server(nickname: String, server: String, information: String) -> String {
			String(localized: .IRC.h19N2(nickname, server, information))
		}

		static func signOnAndIdle(nickname: String, connected: String, idle: String) -> String {
			String(localized: .IRC._6HnO6(nickname, connected, idle))
		}

		static func userhost(
			nickname: String,
			username: String,
			address: String,
			realName: String,
			isHistorical: Bool
		) -> String {
			if isHistorical {
				return String(localized: .IRC._32C87(nickname, username, address, realName))
			}

			return String(localized: .IRC.plgLr(nickname, username, address, realName))
		}
	}

	enum History {
		static func netsplit(
			firstServer: String,
			secondServer: String,
			userCount: UInt,
			nicknames: String
		) -> String {
			String(localized: .IRC.ns1Sp(firstServer, secondServer, userCount, nicknames))
		}

		static func netjoin(
			firstServer: String,
			secondServer: String,
			userCount: UInt,
			nicknames: String
		) -> String {
			String(localized: .IRC.ns2Jn(firstServer, secondServer, userCount, nicknames))
		}

		static func abbreviatedNicknames(_ shown: String, remaining: UInt) -> String {
			String(localized: .IRC.ns3Mr(shown, remaining))
		}
	}
}

enum IRCChannelAccessListKind: Sendable {
	case ban
	case inviteException
	case banException
	case quiet

	init(numeric: UInt) {
		switch numeric {
		case IRCNumeric.banlist.rawValue: self = .ban
		case IRCNumeric.invitelist.rawValue: self = .inviteException
		case IRCNumeric.exceptlist.rawValue: self = .banException
		default: self = .quiet
		}
	}
}

enum IRCChannelAccessListStrings {
	static func entry(
		kind: IRCChannelAccessListKind,
		channelName: String,
		mask: String,
		setBy: String?,
		date: String?
	) -> String {
		if let setBy, let date {
			switch kind {
			case .ban: String(localized: .IRC.c04D01(channelName, mask, setBy, date))
			case .inviteException: String(localized: .IRC.py2Qh1(channelName, mask, setBy, date))
			case .banException: String(localized: .IRC.ov2Ci1(channelName, mask, setBy, date))
			case .quiet: String(localized: .IRC.u5ZAz1(channelName, mask, setBy, date))
			}
		} else {
			switch kind {
			case .ban: String(localized: .IRC.c04D02(channelName, mask))
			case .inviteException: String(localized: .IRC.py2Qh2(channelName, mask))
			case .banException: String(localized: .IRC.ov2Ci2(channelName, mask))
			case .quiet: String(localized: .IRC.u5ZAz2(channelName, mask))
			}
		}
	}
}
