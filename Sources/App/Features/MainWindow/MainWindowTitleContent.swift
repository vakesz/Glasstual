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

	init(client: Client?, channel: Channel?) {
		guard let client else {
			title = ApplicationInfo.applicationName()
			subtitle = ""
			return
		}

		let network = client.networkNameAlt
		let status = Self.connectionStatus(for: client)?.title

		guard let channel else {
			title = network.isEmpty ? ApplicationInfo.applicationName() : network
			subtitle = Self.joined([status, Self.displayNickname(for: client), client.serverAddress])
			return
		}

		title = channel.name
		subtitle = Self.joined([status, network] + Self.conversationDetails(for: channel, on: client))
	}

	private static func joined(_ parts: [String?]) -> String {
		parts.compactMap(nonempty).joined(separator: " · ")
	}

	private static func connectionStatus(for client: Client) -> MainWindowConnectionStatus? {
		if client.isQuitting || client.isDisconnecting {
			return .disconnecting
		}
		if client.isConnected == false, client.isConnecting == false {
			return client.isReconnecting ? .waitingToReconnect : .disconnected
		}
		if client.isConnecting, client.isLoggedIn == false {
			return [.retry, .reconnect].contains(client.connectType) ? .reconnecting : .connecting
		}
		if client.isConnected, client.isLoggedIn == false {
			return .loggingOn
		}
		return nil
	}

	private static func displayNickname(for client: Client) -> String? {
		let nickname = client.userNickname
		guard nickname.isEmpty == false else {
			return nil
		}
		return client.userIsAway ? String(localized: .MainWindow.awayNickname(nickname)) : nickname
	}

	private static func conversationDetails(for channel: Channel, on client: Client) -> [String] {
		switch channel.type {
		case .channel:
			return [MainWindowTitleContent.memberCount(Int(channel.numberOfMembers))]
		case .privateMessage:
			return [client.findUser(channel.name)?.hostmaskFragment].compactMap(nonempty)
		case .directChat:
			return [String(localized: .MainWindow.directChat)]
		case .utility:
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

/// Where a client stands, as the title bar says it.
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
