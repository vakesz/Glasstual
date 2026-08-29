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
@objc(THOPluginDispatcher)
public final nonisolated class PluginDispatcher: NSObject { // nonisolated: value
	/// Holds a rendered message between the render pass and the JavaScript
	/// callback that reports the line has appeared. Entries are evicted as they
	/// are dequeued; a line that is never dequeued ages out with the cache.
	@MainActor
	private static let didPostNewMessageObjectCache =
		NSCache<NSString, THOPluginDidPostNewMessageConcreteObject>()

	@MainActor
	private static var plugins: [PluginItem] {
		SharedApplication.sharedPluginManager().loadedPlugins ?? []
	}

	/// The primary classes of every loaded plugin that publishes `feature`.
	///
	/// The registry-wide check comes first so the common case — no plugin wants
	/// this event — costs one lock and no allocation.
	@MainActor
	private static func handlers<Handler>(for feature: PluginSupportedFeature) -> [Handler] {
		guard SharedApplication.sharedPluginManager().supportsFeature(feature) else {
			return []
		}

		return plugins.compactMap { plugin in
			guard plugin.supportsFeature(feature) else {
				return nil
			}

			return plugin.primaryClass as? Handler
		}
	}

	/// As `handlers(for:)`, but also requires the plugin to have subscribed to
	/// `command`.
	@MainActor
	private static func handlers<Handler>(
		for feature: PluginSupportedFeature,
		subscribedTo command: String,
		commands: (PluginItem) -> [String]?
	) -> [Handler] {
		guard SharedApplication.sharedPluginManager().supportsFeature(feature) else {
			return []
		}

		return plugins.compactMap { plugin in
			guard plugin.supportsFeature(feature),
			      commands(plugin)?.contains(command) == true
			else {
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
		destinedFor textDestination: IRCChannel?,
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

		for handler in handlers where handler.receivedCommand(event) == false {
			return false
		}

		return true
	}

	@MainActor
	public static func dispatchReceivedText(
		_ text: String,
		authoredBy textAuthor: Prefix,
		destinedFor textDestination: IRCChannel?,
		as lineType: TVCLogLineType,
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

		for handler in handlers where handler.receivedText(event) == false {
			return false
		}

		return true
	}

	@objc(interceptServerInput:for:)
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

	@objc(interceptUserInput:command:)
	@MainActor
	public static func interceptUserInput(_ inputObject: Any, command commandString: IRCRemoteCommand) -> Any? {
		let interceptors: [any PluginUserInputIntercepting] = handlers(for: .userInputDataInterception)
		guard interceptors.isEmpty == false else {
			return inputObject
		}

		var returnValue: Any = inputObject

		for interceptor in interceptors {
			guard let returnedValue = interceptor.interceptUserInput(
				PluginUserInput(value: returnValue, commandRawValue: commandString.rawValue)
			) else {
				return nil
			}

			returnValue = merging(returnedValue, into: returnValue)
		}

		return returnValue
	}

	/// Adopts an interceptor's replacement only when it is a string the host can
	/// use, and copies mutable strings so a plugin cannot edit it afterwards.
	@MainActor
	private static func merging(_ returnedValue: Any, into returnValue: Any) -> Any {
		let equal: Bool = if let left = returnValue as? NSObject, let right = returnedValue as? NSObject {
			left.isEqual(right)
		} else {
			false
		}

		guard equal == false,
		      returnedValue is String || returnedValue is NSAttributedString
		else {
			return returnValue
		}

		if returnedValue is NSMutableString || returnedValue is NSMutableAttributedString {
			return (returnedValue as AnyObject).copy()
		}

		return returnedValue
	}

	/// The one dispatch that is not main-actor: the message renderer runs on its
	/// own queue and calls this synchronously, so the renderers are published as
	/// a `Sendable` list of their own.
	@objc(willRenderMessage:forViewController:lineType:memberType:)
	public static func willRenderMessage(
		_ newMessage: String,
		forViewController _: LogController,
		lineType: TVCLogLineType,
		memberType _: TVCLogLineMemberType
	) -> String {
		let renderers = SharedApplication.sharedPluginManager().messageRenderers
		guard renderers.isEmpty == false else {
			return newMessage
		}

		var returnValue = newMessage

		for renderer in renderers {
			guard let returnedValue = renderer.willRenderMessage(
				PluginRenderEvent(message: returnValue, kind: PluginHostAdapter.messageKind(for: lineType))
			), returnedValue.isEmpty == false else {
				continue
			}

			returnValue = returnedValue
		}

		return returnValue
	}

	@objc(userInputCommandInvokedOnClient:commandString:messageString:)
	@MainActor
	public static func userInputCommandInvoked(
		onClient client: IRCClient,
		commandString: String,
		messageString: String
	) {
		let handlers: [any PluginCommandHandling] = handlers(
			for: .subscribedUserInputCommands,
			subscribedTo: commandString.lowercased(),
			commands: \.supportedUserInputCommands
		)
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
	public static func didReceiveJavaScriptPayload(
		_ payloadObject: THOPluginWebViewJavaScriptPayloadConcreteObject,
		fromViewController _: LogController
	) {
		let handlers: [any PluginJavaScriptPayloadHandling] = handlers(for: .webViewJavaScriptPayloads)

		for handler in handlers {
			handler.didReceiveJavaScriptPayload(payloadObject)
		}
	}

	@objc(didReceiveServerInput:onClient:)
	@MainActor
	public static func didReceiveServerInput(_ inputObject: Message, onClient client: IRCClient) {
		let handlers: [any PluginServerInputHandling] = handlers(
			for: .subscribedServerInputCommands,
			subscribedTo: inputObject.command.lowercased(),
			commands: \.supportedServerInputCommands
		)
		guard handlers.isEmpty == false else {
			return
		}

		let pluginClient = PluginHostAdapter.makeClient(client)
		let messageObject = inputObject.didReceiveServerInputConcreteObject()
		messageObject.networkAddress = pluginClient.serverAddress
		messageObject.networkName = pluginClient.networkName

		for handler in handlers {
			handler.didReceiveServerInput(messageObject, client: pluginClient)
		}
	}

	@MainActor
	public static func enqueueDidPostNewMessage(_ messageObject: THOPluginDidPostNewMessageConcreteObject) {
		didPostNewMessageObjectCache.setObject(messageObject, forKey: messageObject.lineNumber as NSString)
	}

	@objc(dequeueDidPostNewMessageWithLineNumber:forViewController:)
	@MainActor
	public static func dequeueDidPostNewMessage(
		withLineNumber messageLineNumber: String,
		forViewController _: LogController
	) {
		let key = messageLineNumber as NSString
		guard let messageObject = didPostNewMessageObjectCache.object(forKey: key) else {
			return
		}

		didPostNewMessageObjectCache.removeObject(forKey: key)

		let handlers: [any PluginPostedMessageHandling] = handlers(for: .newMessagePostedEvent)

		for handler in handlers {
			handler.didPostNewMessage(messageObject)
		}
	}
}
