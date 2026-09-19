// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The complete title-bar projection for one main-window selection.

 A subtitle is one line under the title, and with a unified toolbar it
 truncates: it used to join up to five facts with middots, so the channel's
 mode string survived on a narrow window while the network name -- the fact the
 reader wants -- was cut. What is left is what identifies the conversation:
 where it is, and how big it is. The channel's modes have the Channel menu and
 the modes sheet; the reader's own nickname is on the server row, where the
 title is the network rather than the conversation. */
struct MainWindowTitleContent: Equatable {
	let title: String
	let subtitle: String

	init(session: ServerSession?, conversation: Conversation?) {
		guard let session else {
			title = ApplicationInfo.applicationName()
			subtitle = ""
			return
		}

		let network = session.networkNameAlt
		let status = Self.connectionStatus(for: session)?.title

		guard let conversation else {
			title = network.isEmpty ? ApplicationInfo.applicationName() : network
			subtitle = Self.joined([status, Self.displayNickname(for: session), session.serverAddress])
			return
		}

		title = conversation.name
		subtitle = Self.joined([status, network] + Self.conversationDetails(for: conversation, on: session))
	}

	private static func joined(_ parts: [String?]) -> String {
		parts.compactMap(nonempty).joined(separator: " · ")
	}

	private static func connectionStatus(for session: ServerSession) -> MainWindowConnectionStatus? {
		if session.isQuitting || session.isDisconnecting {
			return .disconnecting
		}
		if session.isConnected == false, session.isConnecting == false {
			return session.isReconnecting ? .waitingToReconnect : .disconnected
		}
		if session.isConnecting, session.isLoggedIn == false {
			return [.retry, .reconnect].contains(session.connectType) ? .reconnecting : .connecting
		}
		if session.isConnected, session.isLoggedIn == false {
			return .loggingOn
		}
		return nil
	}

	private static func displayNickname(for session: ServerSession) -> String? {
		let nickname = session.userNickname
		guard nickname.isEmpty == false else {
			return nil
		}
		return session.away.isAway ? String(localized: .MainWindow.awayNickname(nickname)) : nickname
	}

	private static func conversationDetails(for conversation: Conversation, on session: ServerSession) -> [String] {
		switch conversation.type {
		case .channel:
			return [MainWindowTitleContent.memberCount(Int(conversation.numberOfMembers))]
		case .direct:
			return [session.findUser(conversation.name)?.hostmaskFragment].compactMap(nonempty)
		case .directChat:
			return [String(localized: .MainWindow.directChat)]
		case .console:
			return []
		@unknown default:
			return []
		}
	}

	/** How many people are in the channel.

	 The count reaches the catalog twice: once as text, so the digits are
	 grouped the way the reader's locale groups them, and once as a number, so
	 the noun beside it takes the right plural form. */
	static func memberCount(_ count: Int) -> String {
		String(localized: .MainWindow.mainWindowConnectionStatusUsers(
			count.formatted(.number),
			count: count
		))
	}

	private static func nonempty(_ value: String?) -> String? {
		guard let value, value.isEmpty == false else {
			return nil
		}
		return value
	}
}

// MARK: - Connection status

/// Where a session stands, as the title bar says it.
nonisolated enum MainWindowConnectionStatus {
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
