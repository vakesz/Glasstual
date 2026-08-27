/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
import GlasstualPluginKit

enum MainWindowStrings {
	enum MemberList {
		static var userIsAway: String {
			String(localized: .TVCMainWindow.jkrEd)
		}

		static var userIsNotAway: String {
			String(localized: .TVCMainWindow.gi6Wf)
		}

		static var userIsBot: String {
			String(localized: .TVCMainWindow.b0TAc)
		}

		static var botCaption: String {
			String(localized: .TVCMainWindow.b0TLb)
		}

		static var informationUnavailable: String {
			String(localized: .TVCMainWindow.d859N)
		}

		static var notLoggedIn: String {
			String(localized: .TVCMainWindow.accNl)
		}

		static func loggedIn(account: String) -> String {
			String(localized: .TVCMainWindow.accIn(account))
		}

		static func privilegeDescription(for rank: UserRank) -> String {
			switch rank {
			case .irCopByMode:
				String(localized: .TVCMainWindow.i8TVb)
			case .channelOwner:
				String(localized: .TVCMainWindow.p1ZSc)
			case .superOperator:
				String(localized: .TVCMainWindow.somZo)
			case .normalOperator:
				String(localized: .TVCMainWindow._0KnS5)
			case .halfOperator:
				String(localized: .TVCMainWindow._0NnTe)
			case .voiced:
				String(localized: .TVCMainWindow.ya1Sk)
			default:
				String(localized: .TVCMainWindow.tjjZ2)
			}
		}

		static func sectionTitle(for rank: UserRank) -> String {
			switch rank {
			case .irCopByMode:
				String(localized: .TVCMainWindow.mlsSf)
			case .channelOwner:
				String(localized: .TVCMainWindow.mlsOw)
			case .superOperator:
				String(localized: .TVCMainWindow.mlsAd)
			case .normalOperator:
				String(localized: .TVCMainWindow.mlsOp)
			case .halfOperator:
				String(localized: .TVCMainWindow.mlsHo)
			case .voiced:
				String(localized: .TVCMainWindow.mlsVo)
			default:
				String(localized: .TVCMainWindow.mlsMe)
			}
		}
	}

	enum ConnectionStatus {
		case disconnected
		case waitingToReconnect
		case connecting
		case reconnecting
		case loggingOn
		case disconnecting

		var title: String {
			switch self {
			case .disconnected:
				String(localized: .TVCMainWindow.stDc)
			case .waitingToReconnect:
				String(localized: .TVCMainWindow.stWr)
			case .connecting:
				String(localized: .TVCMainWindow.stCn)
			case .reconnecting:
				String(localized: .TVCMainWindow.stRc)
			case .loggingOn:
				String(localized: .TVCMainWindow.stLo)
			case .disconnecting:
				String(localized: .TVCMainWindow.stDq)
			}
		}
	}

	enum Loading {
		static var configuration: String {
			String(localized: .TVCMainWindow.iphA9)
		}

		static var preferences: String {
			String(localized: .TVCMainWindow._5G1I9)
		}
	}

	enum Conversation {
		static var directChat: String {
			String(localized: .TVCMainWindow.dccCh)
		}

		static var inputPlaceholder: String {
			String(localized: .TVCMainWindow._8R3Ih)
		}

		static var awayNicknameSuffix: String {
			String(localized: .TVCMainWindow.nxzL9)
		}

		static var currentSession: String {
			String(localized: .TVCMainWindow._4YoMk)
		}

		static var noTopic: String {
			String(localized: .TVCMainWindow.vi323)
		}

		static var unreadMessages: String {
			String(localized: .TVCMainWindow.hinUm)
		}

		static func userCount(_ formattedCount: String) -> String {
			String(localized: .TVCMainWindow.stUc(formattedCount))
		}
	}

	enum Toolbar {
		static var connectionSecurity: String {
			String(localized: .TVCMainWindow.tbCs)
		}

		static var toggleServerList: String {
			String(localized: .TVCMainWindow.tbSl)
		}

		static var toggleMemberList: String {
			String(localized: .TVCMainWindow.tbMl)
		}
	}

	enum InputBar {
		static var addServerOrChannel: String {
			String(localized: .TVCMainWindow.ibAd)
		}

		static var searchChannels: String {
			String(localized: .TVCMainWindow.ibSf)
		}

		static var settings: String {
			String(localized: .TVCMainWindow.ibSt)
		}

		static var more: String {
			String(localized: .TVCMainWindow.ibMo)
		}

		static var markAllAsRead: String {
			String(localized: .TVCMainWindow.ibM1)
		}

		static var disableAllNotifications: String {
			String(localized: .TVCMainWindow.ibM2)
		}

		static var addressBook: String {
			String(localized: .TVCMainWindow.ibM3)
		}

		static var fileTransfers: String {
			String(localized: .TVCMainWindow.ibM4)
		}

		static var hideMemberList: String {
			String(localized: .TVCMainWindow.ibM5)
		}
	}

	enum Menu {
		static func serverList(isVisible: Bool) -> String {
			isVisible
				? String(localized: .TVCMainWindow.mnuHsl)
				: String(localized: .TVCMainWindow.mnuSsl)
		}

		static func memberList(isVisible: Bool) -> String {
			isVisible
				? String(localized: .TVCMainWindow.mnuHml)
				: String(localized: .TVCMainWindow.mnuSml)
		}
	}

	enum Dock {
		static func overflowBadge(maximum: String) -> String {
			String(localized: .TVCMainWindow.dkiBg(maximum))
		}
	}

	enum Reply {
		static var anonymousMessage: String {
			String(localized: .TVCMainWindow.rplAn)
		}

		static var cancel: String {
			String(localized: .TVCMainWindow.rplCl)
		}

		static func target(_ nickname: String?) -> String {
			let recipient = nickname.flatMap { $0.isEmpty ? nil : $0 } ?? anonymousMessage
			return String(localized: .TVCMainWindow.rplTo(recipient))
		}
	}

	enum Typing {
		static func caption(for nicknames: [String]) -> String {
			precondition(nicknames.isEmpty == false, "Typing captions require at least one nickname")

			switch nicknames.count {
			case 1:
				return String(localized: .TVCMainWindow.typ1(nicknames[0]))
			case 2:
				return String(localized: .TVCMainWindow.typ2(nicknames[0], nicknames[1]))
			default:
				return String(localized: .TVCMainWindow.typN(String(nicknames.count)))
			}
		}
	}
}
