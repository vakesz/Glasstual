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
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit

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

	init(client: IRCClient?, channel: Channel?) {
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

	private static func connectionStatus(for client: IRCClient) -> MainWindowStrings.ConnectionStatus? {
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

	private static func displayNickname(for client: IRCClient) -> String? {
		let nickname = client.userNickname
		guard nickname.isEmpty == false else {
			return nil
		}
		return client.userIsAway ? MainWindowStrings.Conversation.awayNickname(nickname) : nickname
	}

	private static func conversationDetails(for channel: Channel, on client: IRCClient) -> [String] {
		switch channel.type {
		case .channel:
			return [MainWindowStrings.Conversation.memberCount(Int(channel.numberOfMembers))]
		case .privateMessage:
			return [client.findUser(channel.name)?.hostmaskFragment].compactMap(nonempty)
		case .directChat:
			return [MainWindowStrings.Conversation.directChat]
		case .utility:
			return []
		@unknown default:
			return []
		}
	}

	private static func nonempty(_ value: String?) -> String? {
		guard let value, value.isEmpty == false else {
			return nil
		}
		return value
	}
}
