/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit

/// The complete title-bar projection for one main-window selection.
/// Connection state, identity, and conversation details are composed here so
/// the window only applies the resulting strings to AppKit.
struct MainWindowTitleContent: Equatable {
	let title: String
	let subtitle: String

	init(client: IRCClient?, channel: IRCChannel?) {
		guard let client else {
			title = ApplicationInfo.applicationName()
			subtitle = ""
			return
		}

		let network = client.networkNameAlt
		let status = Self.connectionStatus(for: client)?.title
		let nickname = Self.displayNickname(for: client)
		var subtitleParts = [status, network, nickname].compactMap(Self.nonempty)

		if let channel {
			title = channel.name
			subtitleParts.append(contentsOf: Self.conversationDetails(for: channel, on: client))
		} else {
			title = network.isEmpty ? ApplicationInfo.applicationName() : network
			subtitleParts = [status, nickname, client.serverAddress].compactMap(Self.nonempty)
		}

		subtitle = subtitleParts.joined(separator: " · ")
	}

	private static func connectionStatus(for client: IRCClient) -> MainWindowStrings.ConnectionStatus? {
		if client.isConnected == false, client.isConnecting == false {
			return client.isReconnecting ? .waitingToReconnect : .disconnected
		}
		if client.isConnecting, client.isLoggedIn == false {
			return [.retry, .reconnect].contains(client.connectType) ? .reconnecting : .connecting
		}
		if client.isConnected, client.isLoggedIn == false {
			return .loggingOn
		}
		if client.isQuitting {
			return .disconnecting
		}
		return nil
	}

	private static func displayNickname(for client: IRCClient) -> String? {
		let nickname = client.userNickname
		guard nickname.isEmpty == false else {
			return nil
		}
		return client.userIsAway ? nickname + MainWindowStrings.Conversation.awayNicknameSuffix : nickname
	}

	private static func conversationDetails(for channel: IRCChannel, on client: IRCClient) -> [String] {
		switch channel.type {
		case .channel:
			var details = [
				MainWindowStrings.Conversation.userCount(
					formattedNumber(Int(channel.numberOfMembers)) as String
				),
			]
			if let modes = channel.modeInfo?.stringWithMaskedPassword, modes.count > 1 {
				details.append(modes)
			}
			return details
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
