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
				String(localized: .MainWindow.mainWindowConnectionStatusDisconnected)
			case .waitingToReconnect:
				String(localized: .MainWindow.waitingToReconnect)
			case .connecting:
				String(localized: .MainWindow.mainWindowConnectionStatusConnecting)
			case .reconnecting:
				String(localized: .MainWindow.mainWindowConnectionStatusReconnecting)
			case .loggingOn:
				String(localized: .MainWindow.mainWindowConnectionStatusLogging)
			case .disconnecting:
				String(localized: .MainWindow.mainWindowConnectionStatusDisconnecting)
			}
		}
	}

	enum Loading {
		static var welcomeTitle: String {
			String(localized: .MainWindow.welcomeToGlasstual)
		}

		static var noServersTitle: String {
			String(localized: .MainWindow.noServers)
		}

		static var welcomeDescription: String {
			String(localized: .MainWindow.getStartedDescription)
		}

		static var configuration: String {
			String(localized: .MainWindow.loadingConfiguration)
		}
	}

	enum Formatting {
		static var menuTitle: String {
			String(localized: .MainWindow.ircFormatting)
		}

		static var bold: String {
			String(localized: .MainWindow.bold)
		}

		static var italics: String {
			String(localized: .MainWindow.italics)
		}

		static var monospace: String {
			String(localized: .MainWindow.monospace)
		}

		static var spoiler: String {
			String(localized: .MainWindow.spoiler)
		}

		static var strikethrough: String {
			String(localized: .MainWindow.strikethrough)
		}

		static var underline: String {
			String(localized: .MainWindow.underline)
		}

		static var textColor: String {
			String(localized: .MainWindow.textColor)
		}

		static var backgroundColor: String {
			String(localized: .MainWindow.backgroundColor)
		}

		static var rainbow: String {
			String(localized: .MainWindow.rainbow)
		}

		static var other: String {
			String(localized: .MainWindow.other)
		}
	}

	enum Conversation {
		static var directChat: String {
			String(localized: .MainWindow.directChat)
		}

		/// The message field's name, and what is drawn in it while it is empty.
		static var inputPlaceholder: String {
			String(localized: .MainWindow.sendMessage)
		}

		static func awayNickname(_ nickname: String) -> String {
			String(localized: .MainWindow.awayNickname(nickname))
		}

		static var currentSession: String {
			String(localized: .MainWindow.currentSession)
		}

		static var unreadMessages: String {
			String(localized: .MainWindow.unreadMessages)
		}

		/// The count reaches the catalog twice: once as text, so the digits are
		/// grouped the way the reader's locale groups them, and once as a number,
		/// so the noun beside it takes the right plural form.
		static func memberCount(_ count: Int) -> String {
			String(localized: .MainWindow.mainWindowConnectionStatusUsers(
				count.formatted(.number),
				count: count
			))
		}
	}

	enum Toolbar {
		static var connectionSecurity: String {
			String(localized: .MainWindow.connectionSecurity)
		}

		/// The draggable edge between the conversation and the member list.
		static var memberListWidth: String {
			String(localized: .MainWindow.memberListWidth)
		}

		/// How to move that edge without the pointer.
		static var memberListWidthHint: String {
			String(localized: .MainWindow.memberListWidthHint)
		}
	}

	enum InputBar {
		static var addServerOrChannel: String {
			String(localized: .MainWindow.addServerOrChannel)
		}

		static var filterSidebar: String {
			String(localized: .MainWindow.filterSidebar)
		}

		static var settings: String {
			String(localized: .MainWindow.toolbarInputBarAccessibilitySettings)
		}

		static var more: String {
			String(localized: .MainWindow.toolbarInputBarAccessibilityMore)
		}

		static var markAllAsRead: String {
			String(localized: .MainWindow.markAllAsRead)
		}
	}

	enum Menu {
		static func serverList(isVisible: Bool) -> String {
			isVisible
				? String(localized: .MainWindow.hideServerList)
				: String(localized: .MainWindow.showServerList)
		}

		static func memberList(isVisible: Bool) -> String {
			isVisible
				? String(localized: .MainWindow.dynamicViewWindowMenuHideMemberList)
				: String(localized: .MainWindow.showMemberList)
		}
	}

	enum Dock {
		static func overflowBadge(maximum: String) -> String {
			String(localized: .MainWindow.dockIconBadgeShown(maximum))
		}
	}

	enum Reply {
		static var anonymousMessage: String {
			String(localized: .MainWindow.inputBarReplyBannerMessage)
		}

		static var cancel: String {
			String(localized: .MainWindow.cancelReply)
		}

		static func target(_ nickname: String?) -> String {
			let recipient = nickname.flatMap { $0.isEmpty ? nil : $0 } ?? anonymousMessage
			return String(localized: .MainWindow.inputBarReplyBannerReplying(recipient))
		}
	}

	enum Reaction {
		static var moreEmoji: String {
			String(localized: .MainWindow.moreEmoji)
		}

		static var custom: String {
			String(localized: .MainWindow.customReaction)
		}

		static func reactWith(_ emoji: String) -> String {
			String(localized: .MainWindow.reactWithEmoji(emoji))
		}
	}

	enum Typing {
		static func caption(for nicknames: [String]) -> String {
			precondition(nicknames.isEmpty == false, "Typing captions require at least one nickname")

			switch nicknames.count {
			case 1:
				return String(localized: .MainWindow.isTyping(nicknames[0]))
			case 2:
				return String(localized: .MainWindow.areTyping(nicknames[0], nicknames[1]))
			default:
				return String(localized: .MainWindow.typingCount(nicknames.count))
			}
		}
	}
}
