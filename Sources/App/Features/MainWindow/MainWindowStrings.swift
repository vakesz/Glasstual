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

nonisolated enum MainWindowStrings {
	nonisolated enum MemberList {
		static var userIsAway: String {
			String(localized: .TVCMainWindow.userIsAway)
		}

		static var userIsNotAway: String {
			String(localized: .TVCMainWindow.userIsNotAway)
		}

		static var userIsBot: String {
			String(localized: .TVCMainWindow.userIsABot)
		}

		static var botCaption: String {
			String(localized: .TVCMainWindow.memberListCaptionShownBot)
		}

		static var informationUnavailable: String {
			String(localized: .TVCMainWindow.informationNotAvailable)
		}

		static var notLoggedIn: String {
			String(localized: .TVCMainWindow.notLogged)
		}

		static func loggedIn(account: String) -> String {
			String(localized: .TVCMainWindow.memberAccountStatusDescriptionLogged(account))
		}

		static func privilegeDescription(for rank: UserRank) -> String {
			switch rank {
			case .irCopByMode:
				String(localized: .TVCMainWindow.serverStaffMemberIrcOperator)
			case .channelOwner:
				String(localized: .TVCMainWindow.channelOwner)
			case .superOperator:
				String(localized: .TVCMainWindow.superAdmin)
			case .normalOperator:
				String(localized: .TVCMainWindow.memberPrivilegeDescriptionOperator)
			case .halfOperator:
				String(localized: .TVCMainWindow.halfOp)
			case .voiced:
				String(localized: .TVCMainWindow.memberPrivilegeDescriptionVoice)
			default:
				String(localized: .TVCMainWindow.noPrivileges)
			}
		}

		static func sectionTitle(for rank: UserRank) -> String {
			switch rank {
			case .irCopByMode:
				String(localized: .TVCMainWindow.serverStaff)
			case .channelOwner:
				String(localized: .TVCMainWindow.memberListSectionHeadersOwners)
			case .superOperator:
				String(localized: .TVCMainWindow.memberListSectionHeadersAdmins)
			case .normalOperator:
				String(localized: .TVCMainWindow.memberListSectionHeadersOperators)
			case .halfOperator:
				String(localized: .TVCMainWindow.halfOperators)
			case .voiced:
				String(localized: .TVCMainWindow.memberListSectionHeadersVoiced)
			default:
				String(localized: .TVCMainWindow.memberListSectionHeadersMembers)
			}
		}
	}

	nonisolated enum ConnectionStatus {
		case disconnected
		case waitingToReconnect
		case connecting
		case reconnecting
		case loggingOn
		case disconnecting

		var title: String {
			switch self {
			case .disconnected:
				String(localized: .TVCMainWindow.mainWindowConnectionStatusDisconnected)
			case .waitingToReconnect:
				String(localized: .TVCMainWindow.waitingToReconnect)
			case .connecting:
				String(localized: .TVCMainWindow.mainWindowConnectionStatusConnecting)
			case .reconnecting:
				String(localized: .TVCMainWindow.mainWindowConnectionStatusReconnecting)
			case .loggingOn:
				String(localized: .TVCMainWindow.mainWindowConnectionStatusLogging)
			case .disconnecting:
				String(localized: .TVCMainWindow.mainWindowConnectionStatusDisconnecting)
			}
		}
	}

	nonisolated enum Loading {
		static var configuration: String {
			String(localized: .TVCMainWindow.loadingConfiguration)
		}

		static var preferences: String {
			String(localized: .TVCMainWindow.importingPreferences)
		}
	}

	nonisolated enum Conversation {
		static var directChat: String {
			String(localized: .TVCMainWindow.directChat)
		}

		static var inputPlaceholder: String {
			String(localized: .TVCMainWindow.sendMessage)
		}

		static var awayNicknameSuffix: String {
			String(localized: .TVCMainWindow.suffixAppendedAway)
		}

		static var currentSession: String {
			String(localized: .TVCMainWindow.currentSession)
		}

		static var noTopic: String {
			String(localized: .TVCMainWindow.noTopic)
		}

		static var unreadMessages: String {
			String(localized: .TVCMainWindow.unreadMessages)
		}

		static func userCount(_ formattedCount: String) -> String {
			String(localized: .TVCMainWindow.mainWindowConnectionStatusUsers(formattedCount))
		}
	}

	nonisolated enum Toolbar {
		static var connectionSecurity: String {
			String(localized: .TVCMainWindow.connectionSecurity)
		}

		static var toggleServerList: String {
			String(localized: .TVCMainWindow.toggleServerList)
		}

		static var toggleMemberList: String {
			String(localized: .TVCMainWindow.toggleMemberList)
		}
	}

	nonisolated enum InputBar {
		static var addServerOrChannel: String {
			String(localized: .TVCMainWindow.addServerOrChannel)
		}

		static var searchChannels: String {
			String(localized: .TVCMainWindow.searchChannels)
		}

		static var settings: String {
			String(localized: .TVCMainWindow.toolbarInputBarAccessibilitySettings)
		}

		static var more: String {
			String(localized: .TVCMainWindow.toolbarInputBarAccessibilityMore)
		}

		static var markAllAsRead: String {
			String(localized: .TVCMainWindow.markAllAsRead)
		}

		static var disableAllNotifications: String {
			String(localized: .TVCMainWindow.disableAllNotifications)
		}

		static var addressBook: String {
			String(localized: .TVCMainWindow.addressBook)
		}

		static var fileTransfers: String {
			String(localized: .TVCMainWindow.fileTransfers)
		}

		static var hideMemberList: String {
			String(localized: .TVCMainWindow.hideMemberList)
		}
	}

	nonisolated enum Menu {
		static func serverList(isVisible: Bool) -> String {
			isVisible
				? String(localized: .TVCMainWindow.hideServerList)
				: String(localized: .TVCMainWindow.showServerList)
		}

		static func memberList(isVisible: Bool) -> String {
			isVisible
				? String(localized: .TVCMainWindow.dynamicViewWindowMenuHideMemberList)
				: String(localized: .TVCMainWindow.showMemberList)
		}
	}

	nonisolated enum Dock {
		static func overflowBadge(maximum: String) -> String {
			String(localized: .TVCMainWindow.dockIconBadgeShown(maximum))
		}
	}

	nonisolated enum Reply {
		static var anonymousMessage: String {
			String(localized: .TVCMainWindow.inputBarReplyBannerMessage)
		}

		static var cancel: String {
			String(localized: .TVCMainWindow.cancelReply)
		}

		static func target(_ nickname: String?) -> String {
			let recipient = nickname.flatMap { $0.isEmpty ? nil : $0 } ?? anonymousMessage
			return String(localized: .TVCMainWindow.inputBarReplyBannerReplying(recipient))
		}
	}

	nonisolated enum Typing {
		static func caption(for nicknames: [String]) -> String {
			precondition(nicknames.isEmpty == false, "Typing captions require at least one nickname")

			switch nicknames.count {
			case 1:
				return String(localized: .TVCMainWindow.isTyping(nicknames[0]))
			case 2:
				return String(localized: .TVCMainWindow.areTyping(nicknames[0], nicknames[1]))
			default:
				return String(localized: .TVCMainWindow.peopleAreTyping(String(nicknames.count)))
			}
		}
	}
}
