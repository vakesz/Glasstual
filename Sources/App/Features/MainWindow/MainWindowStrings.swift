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

nonisolated enum MainWindowStrings { // nonisolated: value
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

	enum Loading {
		static var welcomeTitle: String {
			String(localized: .TVCMainWindow.welcomeToGlasstual)
		}

		static var noServersTitle: String {
			String(localized: .TVCMainWindow.noServers)
		}

		static var welcomeDescription: String {
			String(localized: .TVCMainWindow.getStartedDescription)
		}

		static var configuration: String {
			String(localized: .TVCMainWindow.loadingConfiguration)
		}
	}

	enum Formatting {
		static var menuTitle: String {
			String(localized: .TVCMainWindow.ircFormatting)
		}

		static var bold: String {
			String(localized: .TVCMainWindow.bold)
		}

		static var italics: String {
			String(localized: .TVCMainWindow.italics)
		}

		static var monospace: String {
			String(localized: .TVCMainWindow.monospace)
		}

		static var spoiler: String {
			String(localized: .TVCMainWindow.spoiler)
		}

		static var strikethrough: String {
			String(localized: .TVCMainWindow.strikethrough)
		}

		static var underline: String {
			String(localized: .TVCMainWindow.underline)
		}

		static var textColor: String {
			String(localized: .TVCMainWindow.textColor)
		}

		static var backgroundColor: String {
			String(localized: .TVCMainWindow.backgroundColor)
		}

		static var rainbow: String {
			String(localized: .TVCMainWindow.rainbow)
		}

		static var other: String {
			String(localized: .TVCMainWindow.other)
		}
	}

	enum Conversation {
		static var directChat: String {
			String(localized: .TVCMainWindow.directChat)
		}

		/// The message field's name, and what is drawn in it while it is empty.
		static var inputPlaceholder: String {
			String(localized: .TVCMainWindow.sendMessage)
		}

		static func awayNickname(_ nickname: String) -> String {
			String(localized: .TVCMainWindow.awayNickname(nickname))
		}

		static var currentSession: String {
			String(localized: .TVCMainWindow.currentSession)
		}

		static var unreadMessages: String {
			String(localized: .TVCMainWindow.unreadMessages)
		}

		/// The count reaches the catalog twice: once as text, so the digits are
		/// grouped the way the reader's locale groups them, and once as a number,
		/// so the noun beside it takes the right plural form.
		static func memberCount(_ count: Int) -> String {
			String(localized: .TVCMainWindow.mainWindowConnectionStatusUsers(
				formattedNumber(count),
				count: count
			))
		}
	}

	enum Toolbar {
		static var connectionSecurity: String {
			String(localized: .TVCMainWindow.connectionSecurity)
		}

		/// The draggable edge between the conversation and the member list.
		static var memberListWidth: String {
			String(localized: .TVCMainWindow.memberListWidth)
		}

		/// How to move that edge without the pointer.
		static var memberListWidthHint: String {
			String(localized: .TVCMainWindow.memberListWidthHint)
		}
	}

	enum InputBar {
		static var addServerOrChannel: String {
			String(localized: .TVCMainWindow.addServerOrChannel)
		}

		static var filterSidebar: String {
			String(localized: .TVCMainWindow.filterSidebar)
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
	}

	enum Menu {
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

	enum Dock {
		static func overflowBadge(maximum: String) -> String {
			String(localized: .TVCMainWindow.dockIconBadgeShown(maximum))
		}
	}

	enum Reply {
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

	enum Reaction {
		static var moreEmoji: String {
			String(localized: .TVCMainWindow.moreEmoji)
		}

		static var custom: String {
			String(localized: .TVCMainWindow.customReaction)
		}

		static func reactWith(_ emoji: String) -> String {
			String(localized: .TVCMainWindow.reactWithEmoji(emoji))
		}
	}

	enum Typing {
		static func caption(for nicknames: [String]) -> String {
			precondition(nicknames.isEmpty == false, "Typing captions require at least one nickname")

			switch nicknames.count {
			case 1:
				return String(localized: .TVCMainWindow.isTyping(nicknames[0]))
			case 2:
				return String(localized: .TVCMainWindow.areTyping(nicknames[0], nicknames[1]))
			default:
				return String(localized: .TVCMainWindow.typingCount(nicknames.count))
			}
		}
	}
}
