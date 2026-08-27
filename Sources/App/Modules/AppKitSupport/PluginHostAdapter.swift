/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
@_spi(Host) import GlasstualPluginKit

private enum PluginHostMainActorBridge {
	static func sync<Result: Sendable>(
		_ operation: @escaping @MainActor @Sendable () -> Result
	) -> Result {
		if Thread.isMainThread {
			return MainActor.assumeIsolated(operation)
		}

		return DispatchQueue.main.sync {
			MainActor.assumeIsolated(operation)
		}
	}
}

/// Carries host objects and callbacks through a synchronous main-actor handoff.
/// The caller remains blocked, so the wrapped value is never accessed concurrently.
private struct PluginHostTransfer<Value>: @unchecked Sendable {
	let value: Value
}

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

enum PluginHostAdapter {
	static func makeContext() -> PluginHostContext {
		PluginHostMainActorBridge.sync {
			makeContextOnMainActor()
		}
	}

	@MainActor
	private static func makeContextOnMainActor() -> PluginHostContext {
		PluginHostContext(
			defaults: TextualUserDefaults.shared(),
			clients: {
				PluginHostMainActorBridge.sync {
					guard let world = NSObject.applicationController().world else { return [] }
					return world.clientList.map(makeClientOnMainActor)
				}
			},
			selectedChannel: {
				PluginHostMainActorBridge.sync {
					NSObject.applicationController().mainWindow?.selectedChannel.map(makeChannelOnMainActor)
				}
			},
			metrics: {
				PluginHostMainActorBridge.sync {
					makeApplicationMetrics()
				}
			},
			observeConnectionState: observeConnectionState,
			removesFormatting: {
				TextualPreferences.removeAllFormatting()
			}
		)
	}

	static func makeClient(_ client: IRCClient) -> PluginClient {
		let clientReference = PluginHostTransfer(value: client)
		return PluginHostMainActorBridge.sync {
			makeClientOnMainActor(clientReference.value)
		}
	}

	@MainActor
	private static func makeClientOnMainActor(_ client: IRCClient) -> PluginClient {
		let clientReference = PluginHostTransfer(value: client)

		return PluginClient(
			hostObject: client,
			identifier: client.uniqueIdentifier,
			userNickname: client.userNickname,
			networkName: client.networkName,
			serverAddress: client.serverAddress,
			isConnected: client.isConnected,
			isLoggedIn: client.isLoggedIn,
			isIRCop: client.userIsIRCop,
			localUser: client.myself.map(makeUser),
			channels: client.channelList.map(makeChannelOnMainActor),
			isConnectedToZNC: client.isConnectedToZNC,
			zncCertificateChainData: client.zncBouncerCertificateChainData,
			maximumNicknameLength: client.isConnectedToZNC || client.supportInfo.configurationReceived == false
				? PluginHost.defaultMaximumNicknameLength
				: max(client.supportInfo.maximumNicknameLength, 1),
			nicknameMatchesZNCUser: { nickname, zncNickname in
				PluginHostMainActorBridge.sync {
					clientReference.value.nickname(nickname, isZNCUser: zncNickname)
				}
			},
			isChannelName: { name in
				PluginHostMainActorBridge.sync {
					clientReference.value.stringIsChannelName(name)
				}
			},
			findChannel: { name in
				PluginHostMainActorBridge.sync {
					clientReference.value.findChannel(name).map(makeChannelOnMainActor)
				}
			},
			privateMessage: { name in
				PluginHostMainActorBridge.sync {
					clientReference.value.findChannelOrCreate(name, isPrivateMessage: true)
						.map(makeChannelOnMainActor)
				}
			},
			utilityChannel: { name in
				PluginHostMainActorBridge.sync {
					clientReference.value.findChannelOrCreate(name, isUtility: true)
						.map(makeChannelOnMainActor)
				}
			},
			isCapabilityEnabled: { rawValue in
				PluginHostMainActorBridge.sync {
					clientReference.value.isCapabilityEnabled(ClientIRCv3SupportedCapability(rawValue: rawValue))
				}
			},
			printDebug: { message, channel in
				PluginHostMainActorBridge.sync {
					clientReference.value.printDebugInformation(message, in: channel.flatMap(hostChannel))
				}
			},
			sendPrivateMessage: { message, channel in
				PluginHostMainActorBridge.sync {
					guard let channel = hostChannel(channel) else { return }
					clientReference.value.sendPrivmsg(message, to: channel)
				}
			},
			sendCommand: { command in
				PluginHostMainActorBridge.sync {
					clientReference.value.sendCommand(command)
				}
			},
			sendLine: { line in
				PluginHostMainActorBridge.sync {
					clientReference.value.sendLine(line)
				}
			},
			joinChannel: { channelName in
				PluginHostMainActorBridge.sync {
					clientReference.value.joinUnlistedChannel(channelName)
				}
			},
			printMessage: makeMessagePrinter(for: clientReference),
			markUnread: { channel, isHighlight in
				PluginHostMainActorBridge.sync {
					guard let channel = hostChannel(channel) else { return }
					clientReference.value.setUnreadState(for: channel, isHighlight: isHighlight)
				}
			},
			markHighlight: { channel in
				PluginHostMainActorBridge.sync {
					guard let channel = hostChannel(channel) else { return }
					clientReference.value.setHighlightState(for: channel)
				}
			},
			refreshSidebar: {
				PluginHostMainActorBridge.sync {
					NSObject.applicationController().mainWindow?.reloadTreeGroup(clientReference.value)
				}
			}
		)
	}

	static func makeChannel(_ channel: IRCChannel) -> PluginChannel {
		let channelReference = PluginHostTransfer(value: channel)
		return PluginHostMainActorBridge.sync {
			makeChannelOnMainActor(channelReference.value)
		}
	}

	@MainActor
	private static func makeChannelOnMainActor(_ channel: IRCChannel) -> PluginChannel {
		let channelReference = PluginHostTransfer(value: channel)

		return PluginChannel(
			hostObject: channel,
			identifier: channel.uniqueIdentifier,
			name: channel.name,
			type: channel.type,
			isActive: channel.isActive,
			members: (channel.memberList ?? []).map(makeMember),
			autoJoin: {
				PluginHostMainActorBridge.sync { channelReference.value.autoJoin }
			},
			setAutoJoin: { autoJoin in
				PluginHostMainActorBridge.sync { channelReference.value.autoJoin = autoJoin }
			},
			deactivate: {
				PluginHostMainActorBridge.sync { channelReference.value.deactivate() }
			}
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
		guard let mutableMessage = message.mutableCopy() as? MessageMutable,
		      let mutableSender = message.sender.mutableCopy() as? MutablePrefix
		else {
			return message
		}

		mutableSender.nickname = pluginMessage.sender.nickname
		mutableSender.username = pluginMessage.sender.username
		mutableSender.address = pluginMessage.sender.address
		mutableSender.hostmask = pluginMessage.sender.hostmask
		mutableSender.isServer = pluginMessage.sender.isServer

		mutableMessage.sender = mutableSender
		mutableMessage.command = pluginMessage.command
		mutableMessage.params = pluginMessage.parameters
		mutableMessage.isPrintOnlyMessage = pluginMessage.isPrintOnlyMessage

		return mutableMessage.copy() as? Message ?? mutableMessage
	}

	static func messageKind(for lineType: TVCLogLineType) -> PluginMessageKind {
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

	private static func makeMessagePrinter(
		for clientReference: PluginHostTransfer<IRCClient>
	) -> PluginMessagePrinter {
		{ message, nickname, channel, kind, command, receivedAt, isEncrypted, completion in
			let completionReference = PluginHostTransfer(value: completion)
			PluginHostMainActorBridge.sync {
				guard let channel = hostChannel(channel) else { return }
				clientReference.value.print(
					message,
					by: nickname,
					in: channel,
					as: logLineType(for: kind),
					command: command,
					receivedAt: receivedAt,
					isEncrypted: isEncrypted,
					referenceMessage: nil
				) { context in
					completionReference.value(PluginPrintResult(isHighlight: context.isHighlight))
				}
			}
		}
	}

	private static func hostChannel(_ channel: PluginChannel) -> IRCChannel? {
		channel.hostObject as? IRCChannel
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

	@MainActor
	private static func makeApplicationMetrics() -> PluginApplicationMetrics {
		let application = NSObject.applicationController()
		let world = application.world
		let mainWindow = application.mainWindow
		let lastMessageReceived = mainWindow?.selectedClient.map {
			Date.timeIntervalSinceReferenceDate - $0.lastMessageReceived
		} ?? 0
		let visibleLineCount = (world?.clientList ?? []).reduce(0) { total, client in
			total + Int(client.viewController.numberOfLines)
				+ client.channelList.reduce(0) { $0 + Int($1.viewController.numberOfLines) }
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

	private static func observeConnectionState(
		_ handler: @escaping (Bool) -> Void
	) -> PluginObservation {
		let handlerReference = PluginHostTransfer(value: handler)
		let tracker = PluginHostMainActorBridge.sync {
			PluginConnectionTracker(handler: handlerReference.value)
		}
		return PluginObservation {
			PluginHostMainActorBridge.sync {
				tracker.cancel()
			}
		}
	}
}

@MainActor
private final class PluginConnectionTracker {
	private let handler: (Bool) -> Void
	private var clientObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
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
				MainActor.assumeIsolated {
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
		clientObservations.removeAll()
	}

	private func rebuild() {
		let clients = NSObject.applicationController().world.clientList
		let identifiers = Set(clients.map(ObjectIdentifier.init))
		clientObservations = clientObservations.filter { identifiers.contains($0.key) }

		for client in clients where clientObservations[ObjectIdentifier(client)] == nil {
			clientObservations[ObjectIdentifier(client)] = client
				.observe(\.isLoggedIn, options: [.new]) { [weak self] _, _ in
					PluginHostMainActorBridge.sync {
						self?.notify()
					}
				}
		}

		notify()
	}

	private func notify() {
		let isConnected = NSObject.applicationController().world.clientList.contains(where: \.isLoggedIn)
		handler(isConnected)
	}
}
