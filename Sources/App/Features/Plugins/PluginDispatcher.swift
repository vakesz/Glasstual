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

import CocoaExtensions
import Foundation
import GlasstualPluginKit

/// Calls the loaded plugins for one application event.
///
/// Plugin Kit is main-actor isolated end to end, so every dispatch happens
/// inline on the main actor: there is no plugin queue to hop to and no snapshot
/// to hand across it. Nothing is built until a plugin has actually subscribed
/// to the event, because building a `PluginClient` walks the whole channel list.
public nonisolated enum PluginDispatcher { // nonisolated: value
	@MainActor
	private static var plugins: [PluginItem] {
		SharedApplication.sharedPluginManager().loadedPlugins ?? []
	}

	/// The primary classes of every loaded plugin that publishes `feature`.
	///
	/// The registry-wide check comes first so the common case — no plugin wants
	/// this event — costs one lock and no allocation.
	///
	/// - Parameter subscription: A further requirement on the plugin, such as
	/// having subscribed to the command the event carries.
	@MainActor
	private static func handlers<Handler>(
		for feature: PluginSupportedFeature,
		where subscription: ((PluginItem) -> Bool)? = nil
	) -> [Handler] {
		guard SharedApplication.sharedPluginManager().supportsFeature(feature) else {
			return []
		}

		return plugins.compactMap { plugin in
			guard plugin.supportsFeature(feature), subscription?(plugin) != false else {
				return nil
			}

			return plugin.primaryClass as? Handler
		}
	}

	@MainActor
	public static func dispatchReceivedCommand(
		_ command: String,
		withText text: String?,
		authoredBy textAuthor: Prefix,
		destinedFor textDestination: Channel?,
		onClient client: IRCClient,
		receivedAt: Date,
		referenceMessage: Message?
	) -> Bool {
		let handlers: [any PluginIncomingCommandHandling] = handlers(for: .didReceiveCommandEvent)
		guard handlers.isEmpty == false else {
			return true
		}

		let event = PluginIncomingCommandEvent(
			command: command,
			text: text,
			author: PluginHostAdapter.makeSender(textAuthor),
			destination: textDestination.map(PluginHostAdapter.makeChannel),
			client: PluginHostAdapter.makeClient(client),
			receivedAt: receivedAt,
			messageParameters: referenceMessage?.params ?? []
		)

		/* Every handler is asked in turn and the first refusal stops the
		 message, which is what `allSatisfy` does: it calls each handler and
		 returns at the first `false`. */
		return handlers.allSatisfy { $0.receivedCommand(event) }
	}

	@MainActor
	public static func dispatchReceivedText(
		_ text: String,
		authoredBy textAuthor: Prefix,
		destinedFor textDestination: Channel?,
		as lineType: LogLineType,
		onClient client: IRCClient,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool {
		let handlers: [any PluginTextEventHandling] = handlers(for: .didReceivePlainTextMessageEvent)
		guard handlers.isEmpty == false else {
			return true
		}

		let event = PluginTextEvent(
			text: text,
			author: PluginHostAdapter.makeSender(textAuthor),
			destination: textDestination.map(PluginHostAdapter.makeChannel),
			kind: PluginHostAdapter.messageKind(for: lineType),
			client: PluginHostAdapter.makeClient(client),
			receivedAt: receivedAt,
			wasEncrypted: wasEncrypted
		)

		return handlers.allSatisfy { $0.receivedText(event) }
	}

	@MainActor
	public static func interceptServerInput(_ inputObject: Message, for client: IRCClient) -> Message? {
		let interceptors: [any PluginServerMessageIntercepting] = handlers(for: .serverInputDataInterception)
		guard interceptors.isEmpty == false else {
			return inputObject
		}

		let pluginClient = PluginHostAdapter.makeClient(client)
		var returnValue = inputObject

		for interceptor in interceptors {
			guard let intercepted = interceptor.interceptServerInput(
				PluginHostAdapter.makeServerMessage(returnValue),
				client: pluginClient
			) else {
				return nil
			}

			returnValue = PluginHostAdapter.applying(intercepted, to: returnValue)
		}

		return returnValue
	}

	/// The one dispatch that is not main-actor: the message renderer runs on its
	/// own queue and calls this synchronously. Reading the renderers and calling
	/// them is one operation the manager performs, so an unload cannot land
	/// between the two.
	public static func willRenderMessage(_ newMessage: String, lineType: LogLineType) -> String {
		SharedApplication.sharedPluginManager().renderingMessage(
			newMessage,
			kind: PluginHostAdapter.messageKind(for: lineType)
		)
	}

	@MainActor
	public static func userInputCommandInvoked(
		onClient client: IRCClient,
		commandString: String,
		messageString: String
	) {
		let command = commandString.lowercased()
		let handlers: [any PluginCommandHandling] = handlers(for: .subscribedUserInputCommands) {
			$0.supportedUserInputCommands.contains(command)
		}
		guard handlers.isEmpty == false else {
			return
		}

		let host = PluginHostAdapter.makeContext()
		let invocation = PluginCommandInvocation(
			client: PluginHostAdapter.makeClient(client),
			command: commandString.uppercased(),
			message: messageString,
			selectedChannel: host.selectedChannel,
			connectedClients: host.clients
		)

		for handler in handlers {
			handler.userInputCommandInvoked(invocation)
		}
	}

	@MainActor
	public static func didReceiveServerInput(_ inputObject: Message, onClient client: IRCClient) {
		let command = inputObject.command.lowercased()
		let handlers: [any PluginServerInputHandling] = handlers(for: .subscribedServerInputCommands) {
			$0.supportedServerInputCommands.contains(command)
		}
		guard handlers.isEmpty == false else {
			return
		}

		let pluginClient = PluginHostAdapter.makeClient(client)
		var messageObject = inputObject.didReceiveServerInputConcreteObject()
		messageObject.networkAddress = pluginClient.serverAddress
		messageObject.networkName = pluginClient.networkName

		for handler in handlers {
			handler.didReceiveServerInput(messageObject, client: pluginClient)
		}
	}
}
