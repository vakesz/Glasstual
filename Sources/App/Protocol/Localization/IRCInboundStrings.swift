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

nonisolated enum IRCInboundStrings {
	nonisolated enum StandardReply {
		static func failure(command: String, code: String, description: String) -> String {
			String(localized: .IRC.standardRepliesFailWarn(command, code, description))
		}

		static func warning(command: String, code: String, description: String) -> String {
			String(localized: .IRC.warn(command, code, description))
		}

		static func note(command: String, code: String, description: String) -> String {
			String(localized: .IRC.standardRepliesFailWarnNote(command, code, description))
		}
	}

	nonisolated enum ChannelEvent {
		static func modeChanged(sender: String, mode: String) -> String {
			String(localized: .IRC.setsMode(sender, mode))
		}

		static func topicChanged(sender: String, topic: String) -> String {
			String(localized: .IRC.changedTheTopic(sender, topic))
		}

		static func invitation(sender: String, invitee: String, channelName: String) -> String {
			String(localized: .IRC.invitedToJoin(sender, invitee, channelName))
		}

		static func invitation(
			sender: String,
			username: String,
			address: String,
			channelName: String
		) -> String {
			String(localized: .IRC.invitedYouToJoin(sender, username, address, channelName))
		}

		static func mode(_ mode: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelatedMode(mode))
		}

		static func topic(_ topic: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelatedTopic(topic))
		}

		static func topicSet(by nickname: String, date: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelatedSet(nickname, date))
		}

		static func inviting(_ nickname: String, to channelName: String) -> String {
			String(localized: .IRC.invitingToJoin(nickname, channelName))
		}
	}

	nonisolated enum Membership {
		static func joinedQuery(nickname: String) -> String {
			String(localized: .IRC.joinedTheQueryByConnecting(nickname))
		}

		static func joinedChannel(nickname: String, username: String, address: String) -> String {
			String(localized: .IRC.joinedTheChannel(nickname, username, address))
		}

		static func partedChannel(nickname: String, username: String, address: String) -> String {
			String(localized: .IRC.leftTheChannel(nickname, username, address))
		}

		static func eventWithReason(_ event: String, reason: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelated(event, reason))
		}

		static var rejoinScheduled: String {
			String(localized: .IRC.attemptingToRejoinChannelInThree)
		}

		static func kicked(sender: String, target: String, reason: String) -> String {
			String(localized: .IRC.kickedFromTheChannel(sender, target, reason))
		}

		static func quit(nickname: String, username: String, address: String) -> String {
			String(localized: .IRC.leftIrc(nickname, username, address))
		}

		static func eventWithComment(_ event: String, comment: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelatedToIrcEvents(event, comment))
		}

		static func leftQuery(nickname: String) -> String {
			String(localized: .IRC.leftTheQueryByDisconnecting(nickname))
		}

		static func localNicknameChanged(to nickname: String) -> String {
			String(localized: .IRC.youreNowKnown(nickname))
		}

		static func nicknameChanged(from oldNickname: String, to newNickname: String) -> String {
			String(localized: .IRC.isNowKnown(oldNickname, newNickname))
		}
	}
}

extension IRCInboundStrings {
	nonisolated enum Numeric {
		static var saslAuthenticationFailedDisconnecting: String {
			String(localized: .IRC.saslAuthenticationFailedDisconnecting)
		}

		static var endOfSilenceList: String {
			String(localized: .IRC.endOfSilenceList)
		}

		static var utf8EncodingRequired: String {
			String(localized: .IRC.thisServerOnlyAcceptsUtf8)
		}

		static func supportUpdate(previous: String, explanation: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelated2(previous, explanation))
		}

		static func userModes(nickname: String, modes: String) -> String {
			String(localized: .IRC.yourUserModes(nickname, modes))
		}

		static func away(nickname: String, message: String) -> String {
			String(localized: .IRC.isAway(nickname, message))
		}

		static func silenceEntry(_ entry: String) -> String {
			String(localized: .IRC.silenceListEntry(entry))
		}

		static func operatorStatus(networkName: String) -> String {
			String(localized: .IRC.youAreNowAnIrcOperator(networkName))
		}

		static func website(_ website: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelatedWebsite(website))
		}

		static func cannotMessageUnrecognizedUser(_ nickname: String) -> String {
			String(localized: .IRC.youCannotSendPrivateMessages(nickname))
		}

		static func privateMessageBlocked(nickname: String, account: String) -> String {
			String(localized: .IRC.triedToSendYouAPrivate(nickname, account))
		}

		static func nicknameUnavailable(_ nickname: String) -> String {
			String(localized: .IRC.cannotUseNicknameTryingAnother(nickname))
		}
	}

	nonisolated enum Whois {
		static func connection(
			nickname: String,
			address: String,
			realName: String,
			isHistorical: Bool
		) -> String {
			if isHistorical {
				return String(localized: .IRC.miscellaneousMessagesRelatedWasConnected(nickname, address, realName))
			}

			return String(localized: .IRC.isConnected(nickname, address, realName))
		}

		static func channels(nickname: String, channels: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelatedIs(nickname, channels))
		}

		static func bot(nickname: String) -> String {
			String(localized: .IRC.isABot(nickname))
		}

		static func connectedAt(nickname: String, server: String, date: String) -> String {
			String(localized: .IRC.wasConnected(nickname, server, date))
		}

		static func server(nickname: String, server: String, information: String) -> String {
			String(localized: .IRC.miscellaneousMessagesRelatedIsConnected(nickname, server, information))
		}

		static func signOnAndIdle(nickname: String, connected: String, idle: String) -> String {
			String(localized: .IRC.signedOnAtAndHasBeen(nickname, connected, idle))
		}

		static func userhost(
			nickname: String,
			username: String,
			address: String,
			realName: String,
			isHistorical: Bool
		) -> String {
			if isHistorical {
				return String(localized: .IRC.hadUserhostAndRealName(nickname, username, address, realName))
			}

			return String(localized: .IRC.hasUserhostAndRealName(nickname, username, address, realName))
		}
	}

	nonisolated enum History {
		static func netsplit(
			firstServer: String,
			secondServer: String,
			userCount: UInt,
			nicknames: String
		) -> String {
			String(localized: .IRC.netsplitBetweenAndUsersLeft(firstServer, secondServer, userCount, nicknames))
		}

		static func netjoin(
			firstServer: String,
			secondServer: String,
			userCount: UInt,
			nicknames: String
		) -> String {
			String(localized: .IRC.netjoinBetweenAndUsersRejoined(firstServer, secondServer, userCount, nicknames))
		}

		static func abbreviatedNicknames(_ shown: String, remaining: UInt) -> String {
			String(localized: .IRC.netsplitAndNetjoinSummariesMore(shown, remaining))
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

nonisolated enum IRCChannelAccessListStrings {
	static func entry(
		kind: IRCChannelAccessListKind,
		channelName: String,
		mask: String,
		setBy: String?,
		date: String?
	) -> String {
		if let setBy, let date {
			switch kind {
			case .ban: String(localized: .IRC.banInSet(channelName, mask, setBy, date))
			case .inviteException: String(localized: .IRC.inviteExceptionInSet(channelName, mask, setBy, date))
			case .banException: String(localized: .IRC.banExceptionInSet(channelName, mask, setBy, date))
			case .quiet: String(localized: .IRC.quietInSet(channelName, mask, setBy, date))
			}
		} else {
			switch kind {
			case .ban: String(localized: .IRC.banList(channelName, mask))
			case .inviteException: String(localized: .IRC.inviteException(channelName, mask))
			case .banException: String(localized: .IRC.banException(channelName, mask))
			case .quiet: String(localized: .IRC.quietList(channelName, mask))
			}
		}
	}
}
