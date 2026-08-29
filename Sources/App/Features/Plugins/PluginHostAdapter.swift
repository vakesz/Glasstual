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

import AppKit
import Combine
import GlasstualPluginKit

private typealias PluginMessagePrinter = (
	String,
	String?,
	PluginChannel,
	PluginMessageKind,
	String,
	Date,
	Bool,
	@escaping (PluginPrintResult) -> Void
) -> Void

/// Builds the Plugin Kit view of the running application.
///
/// Plugin Kit is main-actor isolated end to end, and so is everything this
/// reads, so the adapter injects plain main-actor closures: no thread hops, no
/// transfer boxes and no runtime lookup by selector name.
enum PluginHostAdapter {
	static func makeContext() -> PluginHostContext {
		PluginHostContext(
			defaults: TextualUserDefaults.container,
			clients: {
				guard let world = AppController.shared.world else { return [] }
				return world.clientList.map(makeClient)
			},
			selectedChannel: {
				AppController.shared.mainWindow?.selectedChannel.map(makeChannel)
			},
			metrics: makeApplicationMetrics,
			applicationSnapshot: makeApplicationSnapshot,
			themeSnapshot: makeThemeSnapshot,
			observeConnectionState: observeConnectionState,
			removesFormatting: {
				TextualPreferences.removeAllFormatting()
			}
		)
	}

	static func makeClient(_ client: IRCClient) -> PluginClient {
		PluginClient(
			identifier: client.uniqueIdentifier,
			userNickname: client.userNickname,
			networkName: client.networkName,
			serverAddress: client.serverAddress,
			isConnected: client.isConnected,
			isLoggedIn: client.isLoggedIn,
			isIRCop: client.userIsIRCop,
			localUser: client.myself.map(makeUser),
			channels: client.channelList.map(makeChannel),
			isConnectedToZNC: client.isConnectedToZNC,
			zncCertificateChainData: client.zncBouncerCertificateChainData,
			maximumNicknameLength: client.isConnectedToZNC || client.supportInfo.configurationReceived == false
				? PluginHost.defaultMaximumNicknameLength
				: max(client.supportInfo.maximumNicknameLength, 1),
			nicknameMatchesZNCUser: { nickname, zncNickname in
				client.nickname(nickname, isZNCUser: zncNickname)
			},
			isChannelName: { name in
				client.stringIsChannelName(name)
			},
			findChannel: { name in
				client.findChannel(name).map(makeChannel)
			},
			privateMessage: { name in
				client.findChannelOrCreate(name, isPrivateMessage: true).map(makeChannel)
			},
			utilityChannel: { name in
				client.findChannelOrCreate(name, isUtility: true).map(makeChannel)
			},
			isCapabilityEnabled: { rawValue in
				client.isCapabilityEnabled(ClientIRCv3SupportedCapability(rawValue: rawValue))
			},
			printDebug: { message, channel in
				client.printDebugInformation(message, in: channel.flatMap { hostChannel($0, on: client) })
			},
			sendPrivateMessage: { message, channel in
				guard let channel = hostChannel(channel, on: client) else { return }
				client.sendPrivmsg(message, to: channel)
			},
			sendCommand: { command in
				client.sendCommand(command)
			},
			sendLine: { line in
				client.sendLine(line)
			},
			joinChannel: { channelName in
				client.joinUnlistedChannel(channelName)
			},
			printMessage: makeMessagePrinter(for: client),
			markUnread: { channel, isHighlight in
				guard let channel = hostChannel(channel, on: client) else { return }
				client.setUnreadState(for: channel, isHighlight: isHighlight)
			},
			markHighlight: { channel in
				guard let channel = hostChannel(channel, on: client) else { return }
				client.setHighlightState(for: channel)
			},
			refreshSidebar: {
				AppController.shared.mainWindow?.reloadTreeGroup(client)
			}
		)
	}

	static func makeChannel(_ channel: IRCChannel) -> PluginChannel {
		PluginChannel(
			identifier: channel.uniqueIdentifier,
			name: channel.name,
			type: channel.type,
			isActive: channel.isActive,
			members: channel.memberList.map(makeMember),
			autoJoin: { channel.autoJoin },
			setAutoJoin: { channel.autoJoin = $0 },
			deactivate: { channel.deactivate() }
		)
	}

	static func makeSender(_ sender: Prefix) -> PluginSender {
		PluginSender(
			nickname: sender.nickname,
			username: sender.username,
			address: sender.address,
			hostmask: sender.hostmask,
			isServer: sender.isServer
		)
	}

	static func makeServerMessage(_ message: Message) -> PluginServerMessage {
		PluginServerMessage(
			sender: makeSender(message.sender),
			command: message.command,
			parameters: message.params,
			isPrintOnlyMessage: message.isPrintOnlyMessage
		)
	}

	static func applying(_ pluginMessage: PluginServerMessage, to message: Message) -> Message {
		let copy = message.duplicate()

		copy.sender = Prefix(
			nickname: pluginMessage.sender.nickname,
			username: pluginMessage.sender.username,
			address: pluginMessage.sender.address,
			hostmask: pluginMessage.sender.hostmask,
			isServer: pluginMessage.sender.isServer
		)
		copy.command = pluginMessage.command
		copy.params = pluginMessage.parameters
		copy.isPrintOnlyMessage = pluginMessage.isPrintOnlyMessage

		return copy
	}

	/// A pure mapping, so the off-main message renderer can call it too.
	nonisolated static func messageKind(for lineType: TVCLogLineType) -> PluginMessageKind {
		switch lineType {
		case .privateMessage:
			.privateMessage
		case .privateMessageNoHighlight:
			.privateMessageNoHighlight
		case .action:
			.action
		case .actionNoHighlight:
			.actionNoHighlight
		case .notice:
			.notice
		case .debug:
			.debug
		default:
			.other
		}
	}

	private static func makeUser(_ user: User) -> PluginUser {
		PluginUser(
			nickname: user.nickname,
			hostmask: user.hostmask,
			address: user.address,
			isIRCop: user.isIRCop
		)
	}

	private static func makeMember(_ member: ChannelUser) -> PluginChannelMember {
		PluginChannelMember(
			user: makeUser(member.user),
			mark: member.mark,
			ranks: member.ranks,
			creationTime: member.creationTime
		)
	}

	private static func makeMessagePrinter(for client: IRCClient) -> PluginMessagePrinter {
		{ message, nickname, channel, kind, command, receivedAt, isEncrypted, completion in
			guard let channel = hostChannel(channel, on: client) else { return }
			client.print(
				message,
				by: nickname,
				in: channel,
				as: logLineType(for: kind),
				command: command,
				receivedAt: receivedAt,
				isEncrypted: isEncrypted,
				referenceMessage: nil
			) { context in
				completion(PluginPrintResult(isHighlight: context.isHighlight))
			}
		}
	}

	/// Plugin Kit values carry the host's identifier rather than the host object
	/// itself, so a plugin can never reach into an app model it was not handed.
	private static func hostChannel(_ channel: PluginChannel, on client: IRCClient) -> IRCChannel? {
		client.channelList.first { $0.uniqueIdentifier == channel.identifier }
	}

	private static func logLineType(for kind: PluginMessageKind) -> TVCLogLineType {
		switch kind {
		case .privateMessage:
			.privateMessage
		case .privateMessageNoHighlight:
			.privateMessageNoHighlight
		case .action:
			.action
		case .actionNoHighlight:
			.actionNoHighlight
		case .notice:
			.notice
		case .debug:
			.debug
		case .other:
			.undefined
		}
	}

	private static func makeApplicationMetrics() -> PluginApplicationMetrics {
		let application: ApplicationController? = AppController.shared
		let world = application?.world
		let mainWindow = application?.mainWindow
		let lastMessageReceived = mainWindow?.selectedClient.map {
			Date.timeIntervalSinceReferenceDate - $0.lastMessageReceived
		} ?? 0
		var visibleLineCount = 0
		for client in world?.clientList ?? [] {
			visibleLineCount += Int(client.logController?.numberOfLines ?? 0)
			for channel in client.channelList {
				visibleLineCount += Int(channel.logController?.numberOfLines ?? 0)
			}
		}

		return PluginApplicationMetrics(
			messagesSent: world?.messagesSent ?? 0,
			messagesReceived: world?.messagesReceived ?? 0,
			bandwidthIn: world?.bandwidthIn ?? 0,
			bandwidthOut: world?.bandwidthOut ?? 0,
			lastMessageReceived: lastMessageReceived,
			visibleLineCount: visibleLineCount,
			usesDarkSidebar: mainWindow?.isUsingDarkAppearance ?? false
		)
	}

	private static func makeApplicationSnapshot() -> PluginApplicationSnapshot {
		PluginApplicationSnapshot(
			timeIntervalSinceLaunch: ApplicationInfo.timeIntervalSinceApplicationLaunch(),
			timeIntervalSinceInstall: ApplicationInfo.timeIntervalSinceApplicationInstall(),
			runCount: ApplicationInfo.applicationRunCount(),
			birthday: ApplicationInfo.applicationBirthday()
		)
	}

	private static func makeThemeSnapshot() -> PluginThemeSnapshot? {
		let controller = SharedApplication.sharedThemeController()
		guard let theme = controller.theme else {
			return nil
		}

		let resolvedAppearance: PluginThemeAppearance = switch theme.appearance {
		case .dark: .dark
		case .light: .light
		case .default:
			SharedApplication.sharedAppearance().properties.isDarkAppearance ? .dark : .light
		}

		return PluginThemeSnapshot(
			name: controller.name,
			storageLocation: storageLocation(for: controller.storageLocation),
			resolvedAppearance: resolvedAppearance
		)
	}

	private static func storageLocation(
		for location: TPCThemeStorageLocation
	) -> PluginThemeStorageLocation {
		switch location {
		case .unknown: .unknown
		case .bundle: .bundled
		case .custom: .custom
		}
	}

	private static func observeConnectionState(
		_ handler: @escaping (Bool) -> Void
	) -> PluginObservation {
		let tracker = PluginConnectionTracker(handler: handler)
		return PluginObservation {
			tracker.cancel()
		}
	}
}

private final class PluginConnectionTracker {
	private let handler: (Bool) -> Void
	private var clientObservations: [ObjectIdentifier: Task<Void, Never>] = [:]
	private var notificationObservers: [NSObjectProtocol] = []

	init(handler: @escaping (Bool) -> Void) {
		self.handler = handler
		let center = NotificationCenter.default
		let names: [Notification.Name] = [
			.ircWorldClientListWasModified,
			.IRCClientDidConnect,
			.IRCClientDidDisconnect,
		]
		notificationObservers = names.map { name in
			center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				// The queue is `.main`, but the callback signature is not
				// isolated, so hop rather than assume.
				Task { @MainActor in
					self?.rebuild()
				}
			}
		}
		rebuild()
	}

	func cancel() {
		let center = NotificationCenter.default
		notificationObservers.forEach(center.removeObserver)
		notificationObservers.removeAll()
		clientObservations.values.forEach { $0.cancel() }
		clientObservations.removeAll()
	}

	private func rebuild() {
		let clients = AppController.shared.world.clientList
		let identifiers = Set(clients.map(ObjectIdentifier.init))
		for (identifier, observation) in clientObservations where identifiers.contains(identifier) == false {
			observation.cancel()
		}

		clientObservations = clientObservations.filter { identifiers.contains($0.key) }

		for client in clients where clientObservations[ObjectIdentifier(client)] == nil {
			/* `observe`'s change handler is nonisolated and had to hop anyway;
			 awaiting the key path inside the task is the same delivery with the
			 isolation stated once. */
			clientObservations[ObjectIdentifier(client)] = Task { @MainActor [weak self] in
				for await _ in client.publisher(for: \.isLoggedIn, options: [.new]).bufferedValues {
					guard let self else {
						return
					}

					notify()
				}
			}
		}

		notify()
	}

	private func notify() {
		let isConnected = AppController.shared.world.clientList.contains(where: \.isLoggedIn)
		handler(isConnected)
	}
}
